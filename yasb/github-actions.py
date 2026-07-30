#!/usr/bin/env python3
"""Read-only GitHub Actions status for YASB using an existing gh login."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path


REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
RUN_FIELDS = "databaseId,number,status,conclusion,workflowName,displayTitle,headBranch,createdAt"
ACTIVE_STATES = {"queued", "in_progress", "pending", "requested", "waiting"}
FAILED_CONCLUSIONS = {"action_required", "cancelled", "failure", "stale", "timed_out"}
CACHE_SECONDS = 15


def selection_file() -> Path:
    app_data = os.environ.get("APPDATA")
    base = Path(app_data) if app_data else Path.home() / ".config"
    return base / "glazewm-config" / "github-actions.json"


def cache_file() -> Path:
    return selection_file().with_name("github-actions-cache.json")


def notification_state_file() -> Path:
    return selection_file().with_name("github-actions-notification.json")


def gh_environment() -> dict[str, str]:
    """Use gh's credential store, never token environment variables."""
    environment = os.environ.copy()
    for variable in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"):
        environment.pop(variable, None)
    return environment


def repositories() -> list[str]:
    try:
        saved = json.loads(selection_file().read_text(encoding="utf-8"))
        if isinstance(saved, dict) and isinstance(saved.get("repositories"), list):
            return list(
                dict.fromkeys(
                    value.strip()
                    for value in saved["repositories"]
                    if isinstance(value, str) and REPOSITORY_PATTERN.fullmatch(value.strip())
                )
            )
    except (OSError, json.JSONDecodeError, TypeError):
        pass
    configured = os.environ.get("YASB_GITHUB_REPOS", "")
    values = re.split(r"[,;\r\n]+", configured)
    return list(dict.fromkeys(value.strip() for value in values if REPOSITORY_PATTERN.fullmatch(value.strip())))


def save_repositories(values: list[str]) -> None:
    selected = list(dict.fromkeys(value.strip() for value in values if REPOSITORY_PATTERN.fullmatch(value.strip())))
    path = selection_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({"repositories": selected, "workflows": {}, "runs": []}, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)
    cache_file().unlink(missing_ok=True)


def selected_workflows() -> dict[str, list[str]]:
    try:
        saved = json.loads(selection_file().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return {}
    configured = saved.get("workflows") if isinstance(saved, dict) else None
    if not isinstance(configured, dict):
        return {}
    result: dict[str, list[str]] = {}
    for repository, workflows in configured.items():
        if not isinstance(repository, str) or not REPOSITORY_PATTERN.fullmatch(repository):
            continue
        if not isinstance(workflows, list):
            continue
        valid = [value.strip() for value in workflows if isinstance(value, str) and value.strip()]
        if valid:
            result[repository] = list(dict.fromkeys(valid))
    return result


def selected_workflow_specifications() -> list[str]:
    return [
        f"{repository} :: {workflow}"
        for repository, workflows in selected_workflows().items()
        for workflow in workflows
    ]


def restore_workflow_from_selected_run() -> list[str]:
    specifications = selected_workflow_specifications()
    if specifications:
        return specifications
    restored: list[str] = []
    for repository, database_id, _ in selected_runs():
        result = run_gh(
            [
                "run", "view", str(database_id), "--repo", repository,
                "--json", "workflowName",
            ]
        )
        if result.returncode:
            continue
        try:
            workflow = str(json.loads(result.stdout).get("workflowName") or "").strip()
        except (json.JSONDecodeError, TypeError):
            workflow = ""
        if workflow:
            restored.append(f"{repository} :: {workflow}")
    if restored:
        save_workflows(restored)
    return restored


def save_workflows(specifications: list[str]) -> None:
    workflows: dict[str, list[str]] = {}
    for specification in specifications:
        parts = specification.split(" :: ", 2)
        if len(parts) < 2:
            continue
        repository, workflow = parts[0].strip(), parts[1].strip()
        if REPOSITORY_PATTERN.fullmatch(repository) and workflow:
            workflows.setdefault(repository, []).append(workflow)
    save_repositories(list(workflows))
    path = selection_file()
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {
                "repositories": list(workflows),
                "workflows": {key: list(dict.fromkeys(value)) for key, value in workflows.items()},
                "runs": [],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)
    cache_file().unlink(missing_ok=True)


def selected_runs() -> list[tuple[str, int, int]]:
    try:
        saved = json.loads(selection_file().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return []
    configured = saved.get("runs") if isinstance(saved, dict) else None
    if not isinstance(configured, list):
        return []
    result: list[tuple[str, int, int]] = []
    for run in configured:
        if not isinstance(run, dict):
            continue
        repository = str(run.get("repository") or "").strip()
        try:
            database_id = int(run.get("database_id"))
            number = int(run.get("number"))
        except (TypeError, ValueError):
            continue
        if REPOSITORY_PATTERN.fullmatch(repository) and database_id > 0 and number > 0:
            result.append((repository, database_id, number))
    return list(dict.fromkeys(result))


def save_runs(specifications: list[str]) -> None:
    runs: list[dict[str, object]] = []
    for specification in specifications:
        parts = specification.split(" :: ", 4)
        if len(parts) < 3:
            continue
        repository = parts[0].strip()
        try:
            database_id = int(parts[1])
            number = int(parts[2].lstrip("#"))
        except ValueError:
            continue
        if REPOSITORY_PATTERN.fullmatch(repository) and database_id > 0 and number > 0:
            runs.append({"repository": repository, "database_id": database_id, "number": number})
    unique = list(
        dict.fromkeys(
            (str(run["repository"]), int(run["database_id"]), int(run["number"]))
            for run in runs
        )
    )
    path = selection_file()
    workflows = selected_workflows()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {
                "repositories": list(dict.fromkeys(repository for repository, _, _ in unique)),
                "workflows": workflows,
                "runs": [
                    {"repository": repository, "database_id": database_id, "number": number}
                    for repository, database_id, number in unique
                ],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)
    cache_file().unlink(missing_ok=True)


def run_gh(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gh", *arguments],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=gh_environment(),
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        check=False,
        timeout=20,
    )


def payload(label: str, details: str, state: str = "unknown") -> dict[str, str]:
    return {"label": label, "details": details, "state": state}


def render_payload(value: dict[str, str]) -> dict[str, str]:
    state = value.get("state", "unknown")
    indicator = {
        "running": "🟡",
        "success": "🟢",
        "failure": "🔴",
        "unknown": "⚪",
    }.get(state, "⚪")
    return {**value, "indicator": indicator}


def status_field(field: str) -> str:
    value = cached_actions_status()
    state = value.get("state", "unknown")
    if field == "display":
        label = value.get("label", "")
        indicator = value.get("indicator", "")
        return f"{indicator} {label}".strip() if label else ""
    if field == "label":
        return value.get("label", "")
    expected_state = {
        "running": "running",
        "success": "success",
        "failure": "failure",
    }.get(field)
    return "\uf111" if state == expected_state else ""


def notify_on_terminal_transition(
    repository: str,
    database_id: int,
    number: int,
    title: str,
    status: str,
    conclusion: str,
) -> None:
    path = notification_state_file()
    key = f"{repository}:{database_id}"
    current = conclusion or status or "unknown"
    try:
        previous = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        previous = {}

    terminal = {
        "success": ("success", f"#{number} succeeded"),
        "failure": ("error", f"#{number} failed"),
        "cancelled": ("warning", f"#{number} was cancelled"),
    }
    previous_state = str(previous.get("state") or "")
    if (
        previous.get("key") == key
        and previous_state in ACTIVE_STATES
        and current in terminal
    ):
        kind, message = terminal[current]
        if title:
            message = f"{message}: {title}"
        script = Path(__file__).with_name("github-actions-notify.ps1")
        if script.is_file():
            try:
                subprocess.Popen(
                    [
                        "powershell.exe",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        str(script),
                        "-Message",
                        message,
                        "-Kind",
                        kind,
                    ],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    creationflags=(
                        getattr(subprocess, "CREATE_NO_WINDOW", 0)
                        | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
                    ),
                    close_fds=True,
                )
            except OSError:
                pass

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"key": key, "state": current}) + "\n",
            encoding="utf-8",
        )
        temporary.replace(path)
    except OSError:
        pass


def cached_actions_status() -> dict[str, str]:
    path = cache_file()
    try:
        cached = json.loads(path.read_text(encoding="utf-8"))
        if time.time() - float(cached["timestamp"]) < CACHE_SECONDS and isinstance(cached["payload"], dict):
            return render_payload(cached["payload"])
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        pass
    value = actions_status()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"timestamp": time.time(), "payload": value}) + "\n",
            encoding="utf-8",
        )
        temporary.replace(path)
    except OSError:
        pass
    return render_payload(value)


def actions_status() -> dict[str, str]:
    if not shutil.which("gh"):
        return payload("CI n/a", "GitHub CLI not installed")

    if run_gh(["auth", "status", "--hostname", "github.com"]).returncode:
        return payload("CI login", "Run gh auth login separately")

    configured_repositories = repositories()
    configured_runs = selected_runs()
    if not configured_repositories:
        return payload("", "", "idle")
    if not configured_runs:
        return payload("", "", "idle")

    running = failed = successful = unknown = 0
    descriptions: list[str] = []
    targets: list[tuple[str, tuple[int, int]]] = [
        (repository, (database_id, number))
        for repository, database_id, number in configured_runs
    ]
    run_ids: list[int] = []
    for repository, selected in targets:
        arguments = [
            "run", "view", str(selected[0]), "--repo", repository, "--json", RUN_FIELDS
        ]
        result = run_gh(arguments)
        if result.returncode:
            unknown += 1
            descriptions.append(f"{repository}: unavailable")
            continue
        try:
            response = json.loads(result.stdout)
            run = response[0] if isinstance(response, list) and response else response
        except (json.JSONDecodeError, TypeError):
            run = None
        if not isinstance(run, dict):
            unknown += 1
            descriptions.append(f"{repository}: no runs")
            continue

        status = str(run.get("status") or "").lower()
        conclusion = str(run.get("conclusion") or "").lower()
        workflow = str(run.get("workflowName") or "Actions")
        try:
            run_id = int(run.get("databaseId"))
        except (TypeError, ValueError):
            run_id = selected[0]
        try:
            run_number = int(run.get("number"))
        except (TypeError, ValueError):
            run_number = selected[1]
        if run_number:
            run_ids.append(run_number)
        title = str(run.get("displayTitle") or "").strip()
        if run_id:
            notify_on_terminal_transition(
                repository,
                run_id,
                run_number,
                title,
                status,
                conclusion,
            )
        branch = str(run.get("headBranch") or "")
        if status in ACTIVE_STATES:
            running += 1
            state = "running"
        elif conclusion == "success":
            successful += 1
            state = "passed"
        elif conclusion in FAILED_CONCLUSIONS:
            failed += 1
            state = conclusion.replace("_", " ")
        else:
            unknown += 1
            state = conclusion or status or "unknown"
        suffix = f" ({branch})" if branch else ""
        run_label = f"#{run_number}" if run_number else "run"
        title_suffix = f" · {title}" if title else ""
        descriptions.append(f"{repository}: {run_label} · {workflow} · {state}{suffix}{title_suffix}")

    if len(targets) == 1 and run_ids:
        label = f"#{run_ids[0]}"
    elif running or failed:
        parts = []
        if running:
            parts.append(f"{running} running")
        if failed:
            parts.append(f"{failed} failed")
        label = "CI " + " ".join(parts)
    elif unknown:
        label = f"CI ?{unknown}"
    else:
        label = f"CI OK {successful}"
    overall_state = "running" if running else "failure" if failed else "unknown" if unknown else "success"
    return payload(label, " | ".join(descriptions), overall_state)


def available_repositories() -> int:
    if not shutil.which("gh"):
        print(json.dumps({"error": "GitHub CLI not installed", "repositories": []}))
        return 1
    if run_gh(["auth", "status", "--hostname", "github.com"]).returncode:
        print(json.dumps({"error": "Run gh auth login separately", "repositories": []}))
        return 1
    result = run_gh(
        [
            "api",
            "--method",
            "GET",
            "--paginate",
            "user/repos",
            "-f",
            "per_page=100",
            "-f",
            "affiliation=owner,collaborator,organization_member",
            "--jq",
            ".[].full_name",
        ]
    )
    if result.returncode:
        print(json.dumps({"error": "Could not load repositories", "repositories": []}))
        return 1
    values = sorted(
        {
            value.strip()
            for value in result.stdout.splitlines()
            if REPOSITORY_PATTERN.fullmatch(value.strip())
        },
        key=str.casefold,
    )
    print(json.dumps({"error": "", "repositories": values}))
    return 0


def available_workflows(configured_repositories: list[str]) -> int:
    values: list[dict[str, str]] = []
    for repository in configured_repositories:
        if not REPOSITORY_PATTERN.fullmatch(repository):
            continue
        result = run_gh(
            [
                "workflow",
                "list",
                "--repo",
                repository,
                "--all",
                "--json",
                "name,path,state",
            ]
        )
        if result.returncode:
            continue
        try:
            workflows = json.loads(result.stdout)
        except json.JSONDecodeError:
            continue
        for workflow in workflows if isinstance(workflows, list) else []:
            path = str(workflow.get("path") or "").strip()
            name = str(workflow.get("name") or path).strip()
            if path:
                values.append(
                    {
                        "label": name,
                        "value": f"{repository} :: {path} :: {name}",
                    }
                )
    values.sort(key=lambda item: item["label"].casefold())
    print(json.dumps({"error": "" if values else "No workflows found", "workflows": values}))
    return 0 if values else 1


def available_runs(workflow_specifications: list[str]) -> int:
    values: list[dict[str, str]] = []
    for specification in workflow_specifications:
        parts = specification.split(" :: ", 2)
        if len(parts) < 2:
            continue
        repository, workflow = parts[0].strip(), parts[1].strip()
        if not REPOSITORY_PATTERN.fullmatch(repository) or not workflow:
            continue
        result = run_gh(
            [
                "run", "list", "--repo", repository, "--workflow", workflow,
                "--limit", "30", "--json", RUN_FIELDS,
            ]
        )
        if result.returncode:
            continue
        try:
            runs = json.loads(result.stdout)
        except json.JSONDecodeError:
            continue
        for run in runs if isinstance(runs, list) else []:
            status = str(run.get("status") or "").strip().lower()
            if status not in ACTIVE_STATES:
                continue
            try:
                database_id = int(run.get("databaseId"))
            except (TypeError, ValueError):
                continue
            title = str(run.get("displayTitle") or run.get("workflowName") or "Actions").strip()
            branch = str(run.get("headBranch") or "").strip()
            created = str(run.get("createdAt") or "").replace("T", " ").replace("Z", " UTC")
            try:
                number = int(run.get("number"))
            except (TypeError, ValueError):
                continue
            status_label = {
                "in_progress": "RUNNING",
                "queued": "QUEUED",
                "pending": "PENDING",
                "requested": "REQUESTED",
                "waiting": "WAITING",
            }.get(status, status.upper().replace("_", " "))
            details = " - ".join(value for value in (branch, status, created) if value)
            values.append(
                {
                    "label": f"{status_label:<9} #{number} - {title}",
                    "details": details,
                    "value": f"{repository} :: {database_id} :: #{number} :: {title}",
                }
            )
    print(json.dumps({"error": "" if values else "No active workflow runs found", "runs": values}))
    return 0 if values else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    field = commands.add_parser("field")
    field.add_argument("name", choices=("display", "label", "running", "success", "failure"))
    commands.add_parser("available-repositories")
    commands.add_parser("selected-workflows")
    workflows = commands.add_parser("available-workflows")
    workflows.add_argument("repositories", nargs="+")
    runs = commands.add_parser("available-runs")
    runs.add_argument("workflows", nargs="+")
    select = commands.add_parser("select-repositories")
    select.add_argument("repositories", nargs="*")
    select_workflows = commands.add_parser("select-workflows")
    select_workflows.add_argument("workflows", nargs="*")
    select_runs = commands.add_parser("select-runs")
    select_runs.add_argument("runs", nargs="*")
    commands.add_parser("clear-repositories")
    args = parser.parse_args()
    if args.command == "status":
        print(json.dumps(cached_actions_status()))
        return 0
    if args.command == "field":
        print(status_field(args.name))
        return 0
    if args.command == "available-repositories":
        return available_repositories()
    if args.command == "selected-workflows":
        print(json.dumps({"workflows": restore_workflow_from_selected_run()}))
        return 0
    if args.command == "available-workflows":
        return available_workflows(args.repositories)
    if args.command == "available-runs":
        return available_runs(args.workflows)
    if args.command == "select-repositories":
        save_repositories(args.repositories)
        return 0
    if args.command == "select-workflows":
        save_workflows(args.workflows)
        return 0
    if args.command == "select-runs":
        save_runs(args.runs)
        return 0
    if args.command == "clear-repositories":
        save_repositories([])
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
