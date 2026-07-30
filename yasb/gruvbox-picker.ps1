$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

function Show-GruvboxPicker {
    param(
        [Parameter(Mandatory)]
        [string[]]$Items,
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Prompt = 'Type to filter',
        [switch]$MultiSelect
    )

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Picker"
        Width="720"
        Height="520"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowActivated="True"
        Background="#32302f"
        Foreground="#ebdbb2"
        FontFamily="Segoe UI"
        Topmost="True">
    <Border BorderBrush="#665c54" BorderThickness="1" CornerRadius="8" Padding="18">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Name="HeaderBar" Grid.Row="0" Margin="0,0,0,14">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="TitleText"
                           Grid.Column="0"
                           FontSize="16"
                           FontWeight="SemiBold"
                           Foreground="#fabd2f"
                           VerticalAlignment="Center"/>
                <Button Name="CloseButton"
                        Grid.Column="1"
                        Content="x"
                        Width="30"
                        Height="28"
                        HorizontalAlignment="Right"
                        Background="Transparent"
                        Foreground="#a89984"
                        BorderThickness="0"
                        FontSize="15"/>
            </Grid>

            <Grid Grid.Row="1" Margin="0,0,0,12">
                <TextBox Name="FilterBox"
                         Height="38"
                         Padding="12,7"
                         Background="#3c3836"
                         Foreground="#ebdbb2"
                         CaretBrush="#fe8019"
                         BorderBrush="#665c54"
                         BorderThickness="1"
                         FontFamily="JetBrainsMono NFP"
                         FontSize="13"/>
                <TextBlock Name="HintText"
                           Margin="13,0"
                           Foreground="#928374"
                           VerticalAlignment="Center"
                           IsHitTestVisible="False"/>
            </Grid>

            <ListBox Name="ItemList"
                     Grid.Row="2"
                     Padding="4"
                     Background="#282828"
                     Foreground="#ebdbb2"
                     BorderBrush="#504945"
                     BorderThickness="1"
                     FontFamily="JetBrainsMono NFP"
                     FontSize="12"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                <ListBox.Resources>
                    <Style TargetType="ListBoxItem">
                        <Setter Property="Padding" Value="10,7"/>
                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                        <Setter Property="Background" Value="Transparent"/>
                        <Setter Property="Foreground" Value="#ebdbb2"/>
                        <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListBoxItem">
                                    <Border Name="ItemBorder"
                                            Padding="{TemplateBinding Padding}"
                                            Background="{TemplateBinding Background}"
                                            CornerRadius="3">
                                        <ContentPresenter/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter Property="Background" Value="#3c3836"/>
                                            <Setter Property="Foreground" Value="#fabd2f"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter Property="Background" Value="#504945"/>
                                            <Setter Property="Foreground" Value="#fabd2f"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                        <Style.Triggers>
                        </Style.Triggers>
                    </Style>
                    <Style TargetType="ScrollBar">
                        <Setter Property="Width" Value="9"/>
                        <Setter Property="Margin" Value="3,3,3,3"/>
                        <Setter Property="Background" Value="#282828"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ScrollBar">
                                    <Grid Background="{TemplateBinding Background}">
                                        <Track Name="PART_Track"
                                               Orientation="{TemplateBinding Orientation}"
                                               IsDirectionReversed="True">
                                            <Track.DecreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageUpCommand"
                                                              Background="Transparent"
                                                              BorderThickness="0"
                                                              Focusable="False"/>
                                            </Track.DecreaseRepeatButton>
                                            <Track.Thumb>
                                                <Thumb Background="#665c54">
                                                    <Thumb.Template>
                                                        <ControlTemplate TargetType="Thumb">
                                                            <Border Background="{TemplateBinding Background}"
                                                                    CornerRadius="4"/>
                                                        </ControlTemplate>
                                                    </Thumb.Template>
                                                </Thumb>
                                            </Track.Thumb>
                                            <Track.IncreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageDownCommand"
                                                              Background="Transparent"
                                                              BorderThickness="0"
                                                              Focusable="False"/>
                                            </Track.IncreaseRepeatButton>
                                        </Track>
                                    </Grid>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </ListBox.Resources>
            </ListBox>

            <DockPanel Grid.Row="3" Margin="0,14,0,0">
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button Name="CancelButton"
                            Content="Cancel"
                            Width="92"
                            Height="34"
                            Margin="0,0,8,0"
                            Background="#3c3836"
                            Foreground="#ebdbb2"
                            BorderBrush="#665c54"/>
                    <Button Name="SelectButton"
                            Content="Select"
                            Width="92"
                            Height="34"
                            Background="#fe8019"
                            Foreground="#282828"
                            BorderBrush="#d65d0e"
                            FontWeight="SemiBold"/>
                </StackPanel>
            </DockPanel>
        </Grid>
    </Border>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $titleText = $window.FindName('TitleText')
    $headerBar = $window.FindName('HeaderBar')
    $filterBox = $window.FindName('FilterBox')
    $hintText = $window.FindName('HintText')
    $itemList = $window.FindName('ItemList')
    $selectButton = $window.FindName('SelectButton')
    $cancelButton = $window.FindName('CancelButton')
    $closeButton = $window.FindName('CloseButton')

    $window.Title = $Title
    $titleText.Text = $Title
    $hintText.Text = $Prompt
    $itemList.SelectionMode = if ($MultiSelect) { 'Extended' } else { 'Single' }
    $allItems = @($Items | Sort-Object -Unique)
    $script:pickerAccepted = $false

    $refresh = {
        $needle = $filterBox.Text.Trim()
        $matches = if ($needle) {
            @($allItems | Where-Object { $_ -like "*$needle*" })
        } else {
            $allItems
        }
        $itemList.ItemsSource = [string[]]$matches
        if ($matches.Count -gt 0 -and -not $MultiSelect) {
            $itemList.SelectedIndex = 0
        }
        $hintText.Visibility = if ($filterBox.Text) { 'Collapsed' } else { 'Visible' }
    }

    $accept = {
        if ($itemList.SelectedItems.Count -gt 0) {
            $script:pickerAccepted = $true
            $window.Close()
        }
    }
    $cancel = {
        $script:pickerAccepted = $false
        $window.Close()
    }

    $filterBox.Add_TextChanged($refresh)
    $filterBox.Add_KeyDown({
        if ($_.Key -eq 'Down') {
            $itemList.Focus()
            $_.Handled = $true
        }
    })
    $itemList.Add_MouseDoubleClick($accept)
    $selectButton.Add_Click($accept)
    $cancelButton.Add_Click($cancel)
    $closeButton.Add_Click($cancel)
    $window.Add_KeyDown({
        if ($_.Key -eq 'Escape') {
            & $cancel
            $_.Handled = $true
        } elseif ($_.Key -eq 'Enter') {
            & $accept
            $_.Handled = $true
        }
    })
    $headerBar.Add_MouseLeftButtonDown({
        if ($_.ButtonState -eq 'Pressed') {
            $window.DragMove()
        }
    })

    & $refresh
    $window.Add_ContentRendered({
        $window.Topmost = $true
        [void]$window.Activate()
        [void]$filterBox.Focus()
    })
    [void]$window.ShowDialog()

    if ($script:pickerAccepted) {
        return @($itemList.SelectedItems | ForEach-Object { [string]$_ })
    }
    return @()
}
