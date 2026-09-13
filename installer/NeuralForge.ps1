#Requires -Version 5.1
<#
.SYNOPSIS
    NeuralForge. Detects your GPU, finds your games, installs, and tunes.

.PARAMETER Console
    Text mode with the same checks, for headless or remote use.
#>

[CmdletBinding()]
param([switch]$Console)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'NeuralForge.Core.ps1')

$Script:Root = Split-Path $PSScriptRoot -Parent

function Start-NfConsole {
    Write-Host ''
    Write-Host '  NeuralForge' -ForegroundColor Cyan
    Write-Host ''

    $gpu = Get-NfGpu
    if (-not $gpu) {
        Write-Host '  No PCI display adapter found.' -ForegroundColor Red
        return 1
    }

    $colour = if (-not $gpu.Viable) { 'Red' }
              elseif ($gpu.Cost -ge 12) { 'Red' }
              elseif ($gpu.Cost -ge 5)  { 'Yellow' }
              else { 'Green' }

    Write-Host "  $($gpu.Name)" -ForegroundColor White
    if ($gpu.Viable) {
        Write-Host ("  {0}  about {1:N1}x an RTX 50" -f $gpu.TierLabel, $gpu.Cost) -ForegroundColor $colour
    } else {
        Write-Host '  Unsupported' -ForegroundColor Red
    }
    Write-Host "  $($gpu.Verdict)" -ForegroundColor Gray
    Write-Host ''

    $rt = Get-NfRuntimeStatus
    Write-Host "  Runtime: $($rt.Message)" -ForegroundColor $(if ($rt.Valid) { 'Green' } else { 'Yellow' })
    Write-Host ''

    if (-not $gpu.Viable) {
        Write-Host '  Nothing to install. This GPU cannot run neural rendering.' -ForegroundColor Red
        Write-Host ''
        return 2
    }

    Write-Host '  Scanning libraries and folders...' -ForegroundColor Gray
    $games = @(Get-NfGames)

    if ($games.Count -eq 0) {
        Write-Host '  No games found.' -ForegroundColor Yellow
        Write-Host ''
        return 1
    }

    Write-Host ''
    for ($i = 0; $i -lt $games.Count; $i++) {
        $g = $games[$i]
        $mark = switch ($g.Status) {
            'Ready'            { 'Green' }
            'Ready via bridge' { 'Green' }
            'Blocked'          { 'Red' }
            default            { 'Yellow' }
        }
        Write-Host ("  {0,3}. " -f ($i + 1)) -NoNewline
        Write-Host ("{0,-40}" -f $g.Name) -NoNewline -ForegroundColor White
        Write-Host ("{0,-9}" -f $g.Api) -NoNewline -ForegroundColor Gray
        Write-Host $g.Status -ForegroundColor $mark
        if ($g.Blocker) { Write-Host "       $($g.Blocker)" -ForegroundColor DarkGray }
    }

    Write-Host ''
    $choice = Read-Host '  Number to install (blank to cancel)'
    if (-not $choice) { return 0 }

    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $games.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        return 1
    }

    try {
        $msg = Install-NeuralForge -Game $games[$index - 1] -Gpu $gpu
        Write-Host ''
        Write-Host "  $msg" -ForegroundColor Green
        Write-Host ''
        return 0
    } catch {
        Write-Host ''
        Write-Host "  $_" -ForegroundColor Red
        Write-Host ''
        return 1
    }
}

$Script:Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NeuralForge" Height="680" Width="1000"
        WindowStartupLocation="CenterScreen" Background="#0F1117">

  <Window.Resources>
    <SolidColorBrush x:Key="Ink"      Color="#E8EAF0"/>
    <SolidColorBrush x:Key="Muted"    Color="#8D94A6"/>
    <SolidColorBrush x:Key="Panel"    Color="#171A23"/>
    <SolidColorBrush x:Key="PanelAlt" Color="#1C202B"/>
    <SolidColorBrush x:Key="Line"     Color="#262B38"/>
    <SolidColorBrush x:Key="Accent"   Color="#3B72F0"/>
    <SolidColorBrush x:Key="Good"     Color="#3FBF87"/>
    <SolidColorBrush x:Key="Warn"     Color="#D9A13B"/>
    <SolidColorBrush x:Key="Bad"      Color="#DE5757"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize"   Value="13"/>
    </Style>

    <Style x:Key="Heading" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize"   Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin"     Value="0,0,0,8"/>
    </Style>

    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground"   Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily"   Value="Segoe UI"/>
      <Setter Property="FontSize"     Value="11"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin"       Value="0,2,0,10"/>
    </Style>

    <Style TargetType="Button">
      <Setter Property="Background"      Value="{StaticResource Accent}"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="FontFamily"      Value="Segoe UI"/>
      <Setter Property="FontSize"        Value="13"/>
      <Setter Property="Padding"         Value="16,7"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize"   Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="b" Background="Transparent" Padding="18,10"
                    BorderThickness="0,0,0,2" BorderBrush="Transparent">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter Property="Foreground" Value="{StaticResource Ink}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Slider">
      <Setter Property="Margin" Value="0,2,0,0"/>
      <Setter Property="IsSnapToTickEnabled" Value="True"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize"   Value="13"/>
      <Setter Property="Margin"     Value="0,6,0,0"/>
    </Style>

    <Style TargetType="DataGridColumnHeader"
           xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
      <Setter Property="Background"      Value="#11141C"/>
      <Setter Property="Foreground"      Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily"      Value="Segoe UI"/>
      <Setter Property="FontSize"        Value="11"/>
      <Setter Property="FontWeight"      Value="SemiBold"/>
      <Setter Property="Padding"         Value="10,8"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="BorderBrush"     Value="{StaticResource Line}"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>

    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="10,0"/>
      <Setter Property="Foreground"      Value="{StaticResource Ink}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#22345E"/>
          <Setter Property="Foreground" Value="{StaticResource Ink}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background"              Value="{StaticResource Panel}"/>
      <Setter Property="Foreground"              Value="{StaticResource Ink}"/>
      <Setter Property="BorderThickness"         Value="0"/>
      <Setter Property="GridLinesVisibility"     Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource Line}"/>
      <Setter Property="RowBackground"           Value="{StaticResource Panel}"/>
      <Setter Property="AlternatingRowBackground" Value="{StaticResource PanelAlt}"/>
      <Setter Property="HeadersVisibility"       Value="Column"/>
      <Setter Property="IsReadOnly"              Value="True"/>
      <Setter Property="SelectionMode"           Value="Single"/>
      <Setter Property="FontFamily"              Value="Segoe UI"/>
      <Setter Property="FontSize"                Value="12"/>
      <Setter Property="RowHeight"               Value="32"/>
      <Setter Property="CanUserResizeRows"       Value="False"/>
      <Setter Property="AutoGenerateColumns"     Value="False"/>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,16">
      <TextBlock Text="NeuralForge" FontSize="26" FontWeight="SemiBold"/>
      <TextBlock x:Name="Version" Text="0.1.0" FontSize="12" Foreground="{StaticResource Muted}"
                 VerticalAlignment="Bottom" Margin="10,0,0,6"/>
    </StackPanel>

    <Border Grid.Row="1" Background="{StaticResource Panel}" CornerRadius="8"
            Padding="18,14" Margin="0,0,0,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0">
          <TextBlock x:Name="GpuName" FontSize="16" FontWeight="SemiBold"/>
          <TextBlock x:Name="GpuTier" FontSize="13" Margin="0,5,0,0"/>
          <TextBlock x:Name="GpuVerdict" Style="{StaticResource Hint}" Margin="0,5,0,0"/>
        </StackPanel>

        <StackPanel Grid.Column="1" VerticalAlignment="Center" MinWidth="250">
          <TextBlock Text="Runtime" FontSize="11" Foreground="{StaticResource Muted}"/>
          <TextBlock x:Name="RuntimeStatus" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,0"/>
          <TextBlock Text="Build" FontSize="11" Foreground="{StaticResource Muted}" Margin="0,10,0,0"/>
          <TextBlock x:Name="BuildStatus" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <TabControl Grid.Row="2" Background="Transparent" BorderThickness="0">

      <TabItem Header="Games">
        <Grid Margin="0,14,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <DataGrid x:Name="GameGrid" Grid.Row="0">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Game"     Binding="{Binding Name}"          Width="*"/>
              <DataGridTextColumn Header="Source"   Binding="{Binding Source}"        Width="80"/>
              <DataGridTextColumn Header="API"      Binding="{Binding Api}"           Width="85"/>
              <DataGridTextColumn Header="Route"    Binding="{Binding Route}"         Width="75"/>
              <DataGridTextColumn Header="Upscaler" Binding="{Binding UpscalerLabel}" Width="95"/>
              <DataGridTextColumn Header="Status"   Binding="{Binding Status}"        Width="130"/>
              <DataGridTextColumn Header="On"       Binding="{Binding Installed}"     Width="60"/>
            </DataGrid.Columns>
          </DataGrid>

          <Border Grid.Row="1" Background="{StaticResource PanelAlt}" CornerRadius="6"
                  Padding="14,10" Margin="0,12,0,0">
            <TextBlock x:Name="Detail" MinHeight="36" TextWrapping="Wrap" FontSize="12"/>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="Tuning">
        <ScrollViewer Margin="0,14,0,0" VerticalScrollBarVisibility="Auto">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="30"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
              <TextBlock Text="Look" Style="{StaticResource Heading}"/>

              <TextBlock x:Name="StructureLabel" Text="Structure  1.00"/>
              <Slider x:Name="Structure" Minimum="0" Maximum="2" Value="1"
                      TickFrequency="0.05" LargeChange="0.1" SmallChange="0.05"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="High frequency response: contact shadows, ambient occlusion, subsurface scattering. 0 is an exact no-op."/>

              <TextBlock x:Name="ToneLabel" Text="Tone  1.00"/>
              <Slider x:Name="Tone" Minimum="0" Maximum="2" Value="1"
                      TickFrequency="0.05" LargeChange="0.1" SmallChange="0.05"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="Low frequency response: broad lighting and colour. Set to 0 to keep the game's exact colours and take only structural detail."/>

              <TextBlock x:Name="SkinLabel" Text="Skin structure  1.00"/>
              <Slider x:Name="SkinStructure" Minimum="0" Maximum="2" Value="1"
                      TickFrequency="0.05" LargeChange="0.1" SmallChange="0.05"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="Multiplier on skin-classified pixels. Around 0.6 with the environment at 1.0 is what most people settle on."/>
            </StackPanel>

            <StackPanel Grid.Column="2">
              <TextBlock Text="Performance" Style="{StaticResource Heading}"/>

              <CheckBox x:Name="AutoTune" Content="Auto-tune" IsChecked="True"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="Walks a fixed quality ladder to hold the budget. Your settings below become the ceiling, never the floor."/>

              <TextBlock x:Name="BudgetLabel" Text="Frame budget  2.0 ms"/>
              <Slider x:Name="Budget" Minimum="0.25" Maximum="20" Value="2"
                      TickFrequency="0.25" LargeChange="1" SmallChange="0.25"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="GPU time the stage may take. budget = 1000/current_fps minus 1000/target_fps, then a little under."/>

              <TextBlock x:Name="ScaleLabel" Text="Working scale  1.00"/>
              <Slider x:Name="Scale" Minimum="0.4" Maximum="1" Value="1"
                      TickFrequency="0.05" LargeChange="0.1" SmallChange="0.05"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="Resolution the network runs at. Cost falls with the square, quality falls much more slowly."/>

              <TextBlock x:Name="PassesLabel" Text="Passes  1"/>
              <Slider x:Name="Passes" Minimum="1" Maximum="3" Value="1" TickFrequency="1"/>

              <TextBlock x:Name="CadenceLabel" Text="Cadence  every frame"/>
              <Slider x:Name="Cadence" Minimum="1" Maximum="4" Value="1" TickFrequency="1"/>
              <TextBlock x:Name="CadenceWarning" Style="{StaticResource Hint}"
                         Foreground="#DE5757" Visibility="Collapsed"
                         Text="Above 2 the runtime's carried temporal state goes stale enough to beat visibly. This is the flicker other tools produce."/>

              <CheckBox x:Name="Selective" Content="Selective refinement" IsChecked="True"/>
              <TextBlock Style="{StaticResource Hint}"
                         Text="Restricts later passes to tiles the first pass changed, usually 15 to 30 percent of them."/>
            </StackPanel>
          </Grid>
        </ScrollViewer>
      </TabItem>

      <TabItem Header="Safety">
        <StackPanel Margin="0,14,0,0" MaxWidth="720" HorizontalAlignment="Left">
          <TextBlock Text="Single-player titles only" Style="{StaticResource Heading}"/>
          <TextBlock TextWrapping="Wrap" Foreground="{StaticResource Muted}">
            NeuralForge modifies a game's render pipeline from inside its process. In a
            title with kernel-level anti-cheat that is indistinguishable from what a cheat
            does, and the consequence lands on your account. Both the installer and the
            module refuse rather than warn.
          </TextBlock>

          <TextBlock Text="Nothing here evades detection" Style="{StaticResource Heading}" Margin="0,18,0,8"/>
          <TextBlock TextWrapping="Wrap" Foreground="{StaticResource Muted}">
            No part of this project hides from anti-cheat, detects whether it is being
            observed, or behaves differently when it is. If a title does not want
            third-party code in its process, the correct response is to stay out.
          </TextBlock>

          <TextBlock Text="Removal is deleting files" Style="{StaticResource Heading}" Margin="0,18,0,8"/>
          <TextBlock TextWrapping="Wrap" Foreground="{StaticResource Muted}">
            Nothing is patched in place and nothing is written to game memory. Every file
            the installer would overwrite is backed up with a manifest first, so Uninstall
            restores the directory exactly.
          </TextBlock>

          <TextBlock Text="The runtime is yours to supply" Style="{StaticResource Heading}" Margin="0,18,0,8"/>
          <TextBlock TextWrapping="Wrap" Foreground="{StaticResource Muted}">
            NeuralForge does not ship, mirror, bundle or download the neural rendering
            runtime, and CI blocks any release archive that contains one. Supply your own
            copy from software you already licence.
          </TextBlock>

          <Button x:Name="OpenDocs" Content="Open documentation" HorizontalAlignment="Left"
                  Margin="0,22,0,0" Background="#333A4A"/>
        </StackPanel>
      </TabItem>

    </TabControl>

    <Grid Grid.Row="3" Margin="0,16,0,0">
      <TextBlock x:Name="Status" VerticalAlignment="Center"
                 Foreground="{StaticResource Muted}" FontSize="12"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="AddFolder" Content="Add folder"  Background="#333A4A" Margin="0,0,8,0"/>
        <Button x:Name="Rescan"    Content="Rescan"      Background="#333A4A" Margin="0,0,8,0"/>
        <Button x:Name="Uninstall" Content="Uninstall"   Background="#8A3B3B" Margin="0,0,8,0"/>
        <Button x:Name="Install"   Content="Install"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

function Start-NfGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Script:Xaml)
    $win    = [Windows.Markup.XamlReader]::Load($reader)

    $ui = @{}
    foreach ($n in @('GpuName','GpuTier','GpuVerdict','RuntimeStatus','BuildStatus',
                     'GameGrid','Detail','Status','Install','Uninstall','Rescan',
                     'AddFolder','OpenDocs','Structure','Tone','SkinStructure',
                     'AutoTune','Budget','Scale','Passes','Cadence','Selective',
                     'StructureLabel','ToneLabel','SkinLabel','BudgetLabel',
                     'ScaleLabel','PassesLabel','CadenceLabel','CadenceWarning')) {
        $ui[$n] = $win.FindName($n)
    }

    $brush = { param($hex) (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

    $Script:ExtraRoots = @()
    $Script:Gpu = Get-NfGpu

    if ($Script:Gpu) {
        $ui.GpuName.Text    = $Script:Gpu.Name
        $ui.GpuVerdict.Text = $Script:Gpu.Verdict

        if ($Script:Gpu.Viable) {
            $ui.GpuTier.Text = '{0}  |  about {1:N1}x an RTX 50  |  suggested budget {2:N1} ms, working scale {3:N2}' -f
                               $Script:Gpu.TierLabel, $Script:Gpu.Cost, $Script:Gpu.Budget, $Script:Gpu.Scale
            $hex = if ($Script:Gpu.Cost -ge 12) { '#DE5757' } elseif ($Script:Gpu.Cost -ge 5) { '#D9A13B' } else { '#3FBF87' }
            $ui.Budget.Value = $Script:Gpu.Budget
            $ui.Scale.Value  = $Script:Gpu.Scale
        } else {
            $ui.GpuTier.Text = 'Unsupported. No tensor cores on this adapter.'
            $hex = '#DE5757'
            $ui.Install.IsEnabled = $false
        }
        $ui.GpuTier.Foreground = & $brush $hex
    } else {
        $ui.GpuName.Text = 'No display adapter detected'
        $ui.Install.IsEnabled = $false
    }

    $rt = Get-NfRuntimeStatus
    $ui.RuntimeStatus.Text       = $rt.Message
    $ui.RuntimeStatus.Foreground = & $brush $(if ($rt.Valid) { '#3FBF87' } else { '#D9A13B' })

    $dll = Join-Path $Script:Root 'build\bin\NeuralForge.dll'
    if (Test-Path -LiteralPath $dll) {
        $ui.BuildStatus.Text       = 'Module built, {0:N0} KB.' -f ((Get-Item $dll).Length / 1KB)
        $ui.BuildStatus.Foreground = & $brush '#3FBF87'
    } else {
        $ui.BuildStatus.Text       = 'Not built. Run build.ps1, or use a release archive.'
        $ui.BuildStatus.Foreground = & $brush '#D9A13B'
    }

    $refresh = {
        $ui.Status.Text = 'Scanning...'
        $win.Dispatcher.Invoke([action]{}, 'Render')

        $games = @(Get-NfGames -ExtraRoots $Script:ExtraRoots)
        $ui.GameGrid.ItemsSource = $games

        $ready = @($games | Where-Object { $_.Status -in @('Ready', 'Ready via bridge') }).Count
        $ui.Status.Text = '{0} found, {1} ready to install' -f $games.Count, $ready
    }

    & $refresh

    $ui.GameGrid.Add_SelectionChanged({
        $g = $ui.GameGrid.SelectedItem
        if (-not $g) { $ui.Detail.Text = ''; return }

        if ($g.Blocker) {
            $ui.Detail.Text = $g.Blocker
            $hex = switch ($g.Status) {
                'Blocked'          { '#DE5757' }
                'Unsupported API'  { '#DE5757' }
                'Ready via bridge' { '#8D94A6' }
                default            { '#D9A13B' }
            }
            $ui.Detail.Foreground = & $brush $hex
        } else {
            $ui.Detail.Text       = '{0} ({1} MB) in {2}   |   upscaler: {3}' -f
                                    $g.Exe, $g.SizeMb, $g.Path, $g.UpscalerLabel
            $ui.Detail.Foreground = & $brush '#8D94A6'
        }

        $installable = $g.Status -notin @('Blocked', 'Unsupported API')
        $ui.Install.IsEnabled   = $installable -and $Script:Gpu -and $Script:Gpu.Viable
        $ui.Uninstall.IsEnabled = [bool]$g.Installed
    })

    $bindSlider = {
        param($slider, $label, $format, $scriptBlock)
        $slider.Add_ValueChanged({
            $label.Text = $format -f $slider.Value
            if ($scriptBlock) { & $scriptBlock }
        }.GetNewClosure())
    }

    & $bindSlider $ui.Structure     $ui.StructureLabel 'Structure  {0:N2}'      $null
    & $bindSlider $ui.Tone          $ui.ToneLabel      'Tone  {0:N2}'           $null
    & $bindSlider $ui.SkinStructure $ui.SkinLabel      'Skin structure  {0:N2}' $null
    & $bindSlider $ui.Budget        $ui.BudgetLabel    'Frame budget  {0:N1} ms' $null
    & $bindSlider $ui.Scale         $ui.ScaleLabel     'Working scale  {0:N2}'  $null
    & $bindSlider $ui.Passes        $ui.PassesLabel    'Passes  {0:N0}'         $null

    $ui.Cadence.Add_ValueChanged({
        $v = [int]$ui.Cadence.Value
        $ui.CadenceLabel.Text = if ($v -eq 1) { 'Cadence  every frame' }
                                else { "Cadence  every {0} frames" -f $v }
        $ui.CadenceWarning.Visibility = if ($v -gt 2) { 'Visible' } else { 'Collapsed' }
    })

    $ui.AutoTune.Add_Click({
        $manual = -not $ui.AutoTune.IsChecked
        foreach ($c in @($ui.Scale, $ui.Passes, $ui.Cadence)) { $c.IsEnabled = $manual }
    })

    $ui.AddFolder.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Pick a folder that contains game directories'
        if ($dialog.ShowDialog() -eq 'OK') {
            $Script:ExtraRoots += $dialog.SelectedPath
            & $refresh
        }
    })

    $ui.Rescan.Add_Click({ & $refresh })

    $ui.OpenDocs.Add_Click({
        Start-Process (Join-Path $Script:Root 'docs\INSTALLATION.md')
    })

    $ui.Install.Add_Click({
        $g = $ui.GameGrid.SelectedItem
        if (-not $g) { return }

        if ($g.Status -notin @('Ready', 'Ready via bridge')) {
            $answer = [Windows.MessageBox]::Show(
                "$($g.Blocker)`n`nInstall anyway?",
                $g.Status, 'YesNo', 'Warning')
            if ($answer -ne 'Yes') { return }
        }

        try {
            $msg = Install-NeuralForge -Game $g -Gpu $Script:Gpu

            $ini = Join-Path $g.Path 'configs\neuralforge.ini'
            [void](Set-NfConfigValue -Path $ini -Values @{
                Structure          = '{0:N2}' -f $ui.Structure.Value
                Tone               = '{0:N2}' -f $ui.Tone.Value
                SkinStructure      = '{0:N2}' -f $ui.SkinStructure.Value
                AutoTune           = $ui.AutoTune.IsChecked.ToString().ToLower()
                BudgetMs           = '{0:N2}' -f $ui.Budget.Value
                WorkingScale       = '{0:N2}' -f $ui.Scale.Value
                Passes             = '{0:N0}' -f $ui.Passes.Value
                Cadence            = '{0:N0}' -f $ui.Cadence.Value
                SelectiveMultipass = $ui.Selective.IsChecked.ToString().ToLower()
            })

            [void][Windows.MessageBox]::Show(
                "$msg`n`nYour tuning was written to the game's config.`n`n" +
                "Supply your own runtime before launching, then start the game, " +
                "enable its upscaler and press Insert.",
                'Installed', 'OK', 'Information')
            & $refresh
        } catch {
            [void][Windows.MessageBox]::Show("$_", 'Install failed', 'OK', 'Error')
        }
    })

    $ui.Uninstall.Add_Click({
        $g = $ui.GameGrid.SelectedItem
        if (-not $g) { return }
        try {
            $msg = Uninstall-NeuralForge -Game $g
            [void][Windows.MessageBox]::Show($msg, 'Removed', 'OK', 'Information')
            & $refresh
        } catch {
            [void][Windows.MessageBox]::Show("$_", 'Uninstall failed', 'OK', 'Error')
        }
    })

    [void]$win.ShowDialog()
    return 0
}

if ($Console) { exit (Start-NfConsole) }

try {
    exit (Start-NfGui)
} catch {
    Write-Host "  Window failed to open ($_). Falling back to console mode." -ForegroundColor Yellow
    exit (Start-NfConsole)
}
