<#
.SYNOPSIS
    Interface graphique (WPF) pour IntuneWaveBuilder : bootstrap d'un nouveau client,
    creation de vagues de deploiement, registre des clients enregistres et consultation
    des logs de creation. Bilingue (anglais par defaut, francais).

.DESCRIPTION
    Pilote les memes fonctions que les scripts en ligne de commande (Bootstrap-TenantApp.ps1,
    New-WaveGroups.ps1), via la logique partagee de WaveGroups.Common.ps1
    (Invoke-TenantBootstrap, Invoke-NewWaveGroups). Aucune duplication de logique Graph.

    Les operations reseau (Graph) s'executent dans un runspace de fond pour ne pas geler
    la fenetre ; les mises a jour d'interface sont marshalees sur le thread UI via le
    Dispatcher de la fenetre.

    Les libelles/messages de la GUI elle-meme (boutons, onglets, validations, confirmations)
    sont bilingues via Get-WaveString/Set-WaveLanguage. Les messages operationnels detailles
    qui remontent du moteur partage (WaveGroups.Common.ps1, utilise aussi par les scripts CLI)
    restent en francais dans les deux langues, pour ne pas faire diverger le comportement des
    scripts CLI.

.EXAMPLE
    .\Show-WaveBuilderGui.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

. (Join-Path $ScriptDir 'WaveGroups.Common.ps1')

# ============================================================================
# XAML
# ============================================================================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="IntuneWaveBuilder" Height="780" Width="1080"
        WindowStartupLocation="CenterScreen" Background="#15171A" Foreground="#E7E9E8"
        FontFamily="Segoe UI">
    <Window.Resources>

        <!-- Palette -->
        <SolidColorBrush x:Key="BgBrush" Color="#15171A"/>
        <SolidColorBrush x:Key="PanelBrush" Color="#1D2023"/>
        <SolidColorBrush x:Key="PanelAltBrush" Color="#262A2E"/>
        <SolidColorBrush x:Key="InputBrush" Color="#21252A"/>
        <SolidColorBrush x:Key="BorderColorBrush" Color="#343A3F"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="#E7E9E8"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#93A19C"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#4FA98C"/>
        <SolidColorBrush x:Key="AccentDarkBrush" Color="#3A8571"/>
        <SolidColorBrush x:Key="AccentSecondaryBrush" Color="#B4A860"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#C1554A"/>

        <!-- Buttons: a Border + white overlay (opacity-animated on hover/press) so every
             variant (primary/secondary/danger) gets consistent hover feedback without
             needing a separate hover color per variant. -->
        <Style x:Key="BaseButtonStyle" TargetType="Button">
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Foreground" Value="#12201C"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="4">
                            <Grid>
                                <Border x:Name="Overlay" Background="White" Opacity="0" CornerRadius="4"/>
                                <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Overlay" Property="Opacity" Value="0.12"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Overlay" Property="Opacity" Value="0.22"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}"/>
        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="{StaticResource PanelAltBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
            <Setter Property="Foreground" Value="#FBF1EF"/>
        </Style>

        <Style TargetType="TextBlock" x:Key="SectionTitle">
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <Style TargetType="TextBlock" x:Key="HintText">
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Padding" Value="0,4,0,2"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="{StaticResource InputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="SelectionBrush" Value="{StaticResource AccentBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                </Trigger>
                <Trigger Property="IsReadOnly" Value="True">
                    <Setter Property="Background" Value="{StaticResource PanelAltBrush}"/>
                    <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- ComboBox: full retemplate, otherwise the dropdown popup stays theme-white -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentBrush}"/>
                                <Setter Property="Foreground" Value="#12201C"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentDarkBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="{StaticResource InputBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3"/>
                            <ToggleButton x:Name="Toggle" Background="Transparent" BorderThickness="0" Focusable="False" ClickMode="Press"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Grid Background="Transparent">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="22"/>
                                            </Grid.ColumnDefinitions>
                                            <Path Grid.Column="1" Data="M0,0 L4,4 L8,0 Z" Fill="{StaticResource TextSecondaryBrush}"
                                                  HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Grid>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                              ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                                              Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True"
                                   Focusable="False" PopupAnimation="Slide">
                                <Border Background="{StaticResource PanelAltBrush}" BorderBrush="{StaticResource BorderColorBrush}" BorderThickness="1"
                                        CornerRadius="3" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="240">
                                    <ScrollViewer>
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- TabControl: flat, underline-style selected indicator -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd" Background="Transparent" BorderBrush="{StaticResource AccentBrush}" BorderThickness="0,0,0,0" Padding="16,10">
                            <ContentPresenter x:Name="ContentSite" ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="BorderThickness" Value="0,0,0,2"/>
                                <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- DataGrid -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="{StaticResource PanelBrush}"/>
            <Setter Property="RowBackground" Value="Transparent"/>
            <Setter Property="AlternatingRowBackground" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="VerticalGridLinesBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{StaticResource PanelAltBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Padding" Value="8,7"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="Background" Value="Transparent"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource PanelAltBrush}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource AccentDarkBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="8,4"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="White"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- ListBox -->
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{StaticResource PanelBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderColorBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource PanelAltBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentDarkBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Minimal flat scrollbars (both orientations share one Track-based template) -->
        <Style x:Key="ThumbStyle" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border Background="{StaticResource BorderColorBrush}" CornerRadius="4"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Track x:Name="PART_Track" IsDirectionReversed="True">
                            <Track.Thumb>
                                <Thumb Style="{StaticResource ThumbStyle}"/>
                            </Track.Thumb>
                            <Track.DecreaseRepeatButton>
                                <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                            </Track.DecreaseRepeatButton>
                            <Track.IncreaseRepeatButton>
                                <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                            </Track.IncreaseRepeatButton>
                        </Track>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Vertical">
                    <Setter Property="Width" Value="10"/>
                </Trigger>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Height" Value="10"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Language-switch badges (FR/EN): WPF does not reliably render color flag-emoji
             glyphs (a platform limitation, not a font/encoding issue), so a plain two-letter
             badge is used instead - active state is applied in code (Set-WaveLanguage) via a
             local Background override. -->
        <Style x:Key="FlagButton" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="{StaticResource PanelAltBrush}"/>
            <Setter Property="Padding" Value="9,4"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="MinWidth" Value="30"/>
        </Style>
    </Window.Resources>

    <Grid Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="200"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource BorderColorBrush}" BorderThickness="0,0,0,1" Padding="20,14">
            <Grid>
                <StackPanel Orientation="Vertical">
                    <TextBlock Text="IntuneWaveBuilder" FontSize="20" FontWeight="Bold" Foreground="{StaticResource AccentBrush}"/>
                    <TextBlock x:Name="AppSubtitleText" Text="Intune deployment waves - Entra ID security groups" Foreground="{StaticResource TextSecondaryBrush}"/>
                </StackPanel>
                <StackPanel Orientation="Vertical" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button x:Name="LangFrButton" Content="FR" Style="{StaticResource FlagButton}" ToolTip="Français" Cursor="Hand"/>
                        <Button x:Name="LangEnButton" Content="EN" Style="{StaticResource FlagButton}" ToolTip="English" Cursor="Hand" Margin="6,0,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="RegistryCountText" Text="0 client(s) registered" Foreground="{StaticResource TextSecondaryBrush}"
                               HorizontalAlignment="Right" Margin="0,6,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="1" Margin="0">

            <!-- Tab 1: Bootstrap -->
            <TabItem x:Name="TabBootstrap" Header="New client (Bootstrap)">
              <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0">
                        <TextBlock x:Name="BootstrapSectionTitle" Text="Dedicated App Registration" Style="{StaticResource SectionTitle}"/>
                        <TextBlock x:Name="BootstrapHint" Style="{StaticResource HintText}" Text="Run once per client tenant, signed in with a Global Admin account."/>

                        <Label x:Name="LabelClientName" Content="Client name"/>
                        <TextBox x:Name="BootstrapClientNameBox" ToolTip="Short, unique name, e.g. Contoso"/>

                        <Label x:Name="LabelCertYears" Content="Certificate validity (years)"/>
                        <ComboBox x:Name="BootstrapCertYearsCombo" SelectedIndex="1">
                            <ComboBoxItem Content="1"/>
                            <ComboBoxItem Content="2"/>
                            <ComboBoxItem Content="3"/>
                            <ComboBoxItem Content="5"/>
                            <ComboBoxItem Content="10"/>
                        </ComboBox>

                        <Button x:Name="BootstrapRunButton" Content="Sign in and create" Margin="0,16,0,0" HorizontalAlignment="Left"/>
                        <TextBlock x:Name="BootstrapInteractiveHint" Style="{StaticResource HintText}" Margin="0,8,0,0" Text="A Microsoft sign-in window will open."/>
                    </StackPanel>

                    <StackPanel Grid.Column="2">
                        <TextBlock x:Name="ResultSectionTitle" Text="Result" Style="{StaticResource SectionTitle}"/>
                        <Label Content="TenantId"/>
                        <TextBox x:Name="BootstrapResultTenantBox" IsReadOnly="True"/>
                        <Label Content="ClientId"/>
                        <TextBox x:Name="BootstrapResultClientBox" IsReadOnly="True"/>
                        <Label Content="Certificate Thumbprint"/>
                        <TextBox x:Name="BootstrapResultThumbBox" IsReadOnly="True"/>
                        <Button x:Name="BootstrapCopyButton" Content="Copy parameters" Style="{StaticResource SecondaryButton}" Margin="0,12,0,0" HorizontalAlignment="Left" IsEnabled="False"/>
                    </StackPanel>
                </Grid>
              </ScrollViewer>
            </TabItem>

            <!-- Tab 2: Create waves -->
            <TabItem x:Name="TabWaves" Header="Create waves">
              <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="360"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0">
                        <TextBlock x:Name="WavesSectionTitle" Text="Parameters" Style="{StaticResource SectionTitle}"/>

                        <Label x:Name="LabelClient" Content="Client"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox x:Name="WaveClientCombo" Grid.Column="0" DisplayMemberPath="ClientName"/>
                            <Button x:Name="WaveClientRefreshButton" Grid.Column="1" Content="Refresh" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                        </Grid>

                        <Label x:Name="LabelTargetType" Content="Target type"/>
                        <StackPanel Orientation="Horizontal">
                            <RadioButton x:Name="TargetDeviceRadio" Content="Devices" GroupName="TargetType" IsChecked="True" VerticalAlignment="Center" Margin="0,0,20,0"/>
                            <RadioButton x:Name="TargetUserRadio" Content="Users" GroupName="TargetType" VerticalAlignment="Center"/>
                        </StackPanel>

                        <Label x:Name="LabelPlatform" Content="Platform (devices only)"/>
                        <ComboBox x:Name="PlatformCombo" SelectedIndex="0">
                            <ComboBoxItem Content="All"/>
                            <ComboBoxItem Content="Windows"/>
                            <ComboBoxItem Content="iOS"/>
                            <ComboBoxItem Content="Android"/>
                            <ComboBoxItem Content="Linux"/>
                            <ComboBoxItem Content="macOS"/>
                        </ComboBox>

                        <Label x:Name="LabelDeploymentName" Content="Deployment name"/>
                        <TextBox x:Name="DeploymentNameBox" ToolTip="Used in the wave group names"/>

                        <TextBlock x:Name="WavesSectionTitle2" Text="Waves" Style="{StaticResource SectionTitle}" Margin="0,16,0,8"/>
                        <DataGrid x:Name="WaveGrid" Height="180" AutoGenerateColumns="False" CanUserAddRows="False"
                                  CanUserDeleteRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Wave" Binding="{Binding Wave}" IsReadOnly="True" Width="70"/>
                                <DataGridTextColumn Header="Percentage" Binding="{Binding Percentage}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>
                        <Grid Margin="0,8,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="WaveAddButton" Grid.Column="0" Content="+ Wave" Style="{StaticResource SecondaryButton}"/>
                            <Button x:Name="WaveRemoveButton" Grid.Column="1" Content="- Wave" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                            <TextBlock x:Name="WaveTotalText" Grid.Column="2" Text="Total: 0%" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="{StaticResource TextSecondaryBrush}"/>
                        </Grid>

                        <Button x:Name="WaveRunButton" Content="Launch wave creation" Margin="0,20,0,20" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2">
                        <TextBlock x:Name="AboutSectionTitle" Text="About this operation" Style="{StaticResource SectionTitle}"/>
                        <TextBlock x:Name="AboutHint1" Style="{StaticResource HintText}" Text="The selection pool is always restricted to Intune-managed devices."/>
                        <TextBlock x:Name="AboutHint2" Style="{StaticResource HintText}" Text="Before any creation, the actually-connected tenant is shown for confirmation."/>
                        <TextBlock x:Name="AboutHint3" Style="{StaticResource HintText}" Text="A CSV per group is written to the Logs folder."/>
                    </StackPanel>
                </Grid>
              </ScrollViewer>
            </TabItem>

            <!-- Tab 3: Client registry -->
            <TabItem x:Name="TabRegistry" Header="Client registry">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock x:Name="RegistryHint" Grid.Row="0" Style="{StaticResource HintText}" Text="Local reference only."/>

                    <DataGrid x:Name="RegistryGrid" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True"
                              HeadersVisibility="Column" GridLinesVisibility="Horizontal" SelectionMode="Single">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Client" Binding="{Binding ClientName}" Width="160"/>
                            <DataGridTextColumn Header="TenantId" Binding="{Binding TenantId}" Width="260"/>
                            <DataGridTextColumn Header="ClientId" Binding="{Binding ClientId}" Width="260"/>
                            <DataGridTextColumn Header="Certificate Thumbprint" Binding="{Binding CertThumbprint}" Width="220"/>
                            <DataGridTextColumn Header="Created (UTC)" Binding="{Binding CreatedUtc}" Width="*"/>
                        </DataGrid.Columns>
                    </DataGrid>

                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button x:Name="RegistryRefreshButton" Content="Refresh" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="RegistryCopyButton" Content="Copy parameters" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                        <Button x:Name="RegistryDeleteButton" Content="Remove from registry" Style="{StaticResource DangerButton}" Margin="8,0,0,0"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- Tab 4: Logs -->
            <TabItem x:Name="TabLogs" Header="Logs">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="320"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <Button x:Name="LogsRefreshButton" Content="Refresh" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="LogsOpenFolderButton" Content="Open folder" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                    </StackPanel>
                    <ListBox x:Name="LogsFileList" Grid.Row="1" Grid.Column="0"/>

                    <DataGrid x:Name="LogsContentGrid" Grid.Row="0" Grid.RowSpan="2" Grid.Column="2" AutoGenerateColumns="True" IsReadOnly="True"
                              HeadersVisibility="Column" GridLinesVisibility="Horizontal"/>
                </Grid>
            </TabItem>

        </TabControl>

        <!-- Log panel -->
        <Border Grid.Row="2" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource BorderColorBrush}" BorderThickness="0,1,0,1">
            <Grid Margin="20,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0">
                    <TextBlock x:Name="JournalSectionTitle" Text="Log" Style="{StaticResource SectionTitle}" Margin="0,0,0,6"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button x:Name="LogCopyButton" Content="Copy" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="LogClearButton" Content="Clear" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                    </StackPanel>
                </Grid>
                <TextBox x:Name="LogBox" Grid.Row="1" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"
                         Background="{StaticResource InputBrush}" Foreground="{StaticResource TextPrimaryBrush}"
                         BorderThickness="1" BorderBrush="{StaticResource BorderColorBrush}"/>
            </Grid>
        </Border>

        <!-- Status bar -->
        <Border Grid.Row="3" Background="{StaticResource PanelBrush}" BorderBrush="{StaticResource BorderColorBrush}" BorderThickness="0,1,0,0" Padding="20,6">
            <TextBlock x:Name="StatusText" Text="Ready." Foreground="{StaticResource TextSecondaryBrush}"/>
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ============================================================================
# Control lookups
# ============================================================================
$controlNames = @(
    'AppSubtitleText','RegistryCountText','LangFrButton','LangEnButton',
    'TabBootstrap','TabWaves','TabRegistry','TabLogs',
    'BootstrapSectionTitle','BootstrapHint','LabelClientName','BootstrapClientNameBox',
    'LabelCertYears','BootstrapCertYearsCombo','BootstrapRunButton','BootstrapInteractiveHint',
    'ResultSectionTitle','BootstrapResultTenantBox','BootstrapResultClientBox','BootstrapResultThumbBox','BootstrapCopyButton',
    'WavesSectionTitle','LabelClient','WaveClientCombo','WaveClientRefreshButton',
    'LabelTargetType','TargetDeviceRadio','TargetUserRadio','LabelPlatform','PlatformCombo',
    'LabelDeploymentName','DeploymentNameBox','WavesSectionTitle2','WaveGrid','WaveAddButton','WaveRemoveButton','WaveTotalText','WaveRunButton',
    'AboutSectionTitle','AboutHint1','AboutHint2','AboutHint3',
    'RegistryHint','RegistryGrid','RegistryRefreshButton','RegistryCopyButton','RegistryDeleteButton',
    'LogsRefreshButton','LogsOpenFolderButton','LogsFileList','LogsContentGrid',
    'JournalSectionTitle','LogBox','LogCopyButton','LogClearButton','StatusText'
)
$ctrl = @{}
foreach ($name in $controlNames) { $ctrl[$name] = $window.FindName($name) }

# ============================================================================
# Localization
# ============================================================================
$script:CurrentLang = 'en'
$script:Strings = @{
    en = @{
        AppSubtitle              = 'Intune deployment waves - Entra ID security groups'
        RegistryCountFormat      = '{0} client(s) registered'
        TabBootstrap              = 'New client (Bootstrap)'
        TabWaves                  = 'Create waves'
        TabRegistry                = 'Client registry'
        TabLogs                     = 'Logs'
        BootstrapSectionTitle    = 'Dedicated App Registration'
        BootstrapHint             = 'Run once per client tenant, signed in with a Global Admin account (or Application Administrator + Privileged Role Administrator). Creates an isolated App Registration, a local certificate, and grants admin consent for the minimal required permissions.'
        LabelClientName          = 'Client name'
        TooltipClientName        = 'Short, unique name, e.g. Contoso'
        LabelCertYears            = 'Certificate validity (years)'
        ButtonBootstrapRun       = 'Sign in and create'
        HintBootstrapInteractive = 'A Microsoft sign-in window will open (interactive authentication).'
        SectionResult              = 'Result'
        ButtonCopyParams          = 'Copy parameters'
        SectionParams              = 'Parameters'
        LabelClient                = 'Client'
        ButtonRefresh              = 'Refresh'
        LabelTargetType           = 'Target type'
        RadioDevices                = 'Devices'
        RadioUsers                  = 'Users'
        LabelPlatform              = 'Platform (devices only)'
        LabelDeploymentName      = 'Deployment name'
        TooltipDeploymentName    = 'Used in the wave group names'
        SectionWaves               = 'Waves'
        ColWave                      = 'Wave'
        ColPercentage              = 'Percentage'
        ButtonAddWave              = '+ Wave'
        ButtonRemoveWave         = '- Wave'
        WaveTotalFormat           = 'Total: {0}%'
        ButtonRunWaves             = 'Launch wave creation'
        SectionAbout               = 'About this operation'
        HintAbout1                  = 'The selection pool is always restricted to Intune-managed devices (managementState = managed). Each wave draws its percentage (computed on the original pool size) WITHOUT REPLACEMENT: an entity already assigned to a wave can never be selected by a later wave.'
        HintAbout2                  = 'Before any creation, the actually-connected tenant (name, domain, TenantId) is shown for confirmation - protection against picking the wrong client.'
        HintAbout3                  = 'A CSV per group (members added / failures) is written to the Logs folder, browsable in the Logs tab.'
        HintRegistry                = 'Local reference only (%LOCALAPPDATA%\IntuneWaveBuilder\clients.json). Removing an entry here does NOT delete the App Registration or the certificate in the tenant - it only removes the local shortcut.'
        ColClient                    = 'Client'
        ColCertThumb               = 'Certificate Thumbprint'
        ColCreatedUtc              = 'Created (UTC)'
        ButtonDeleteRegistry     = 'Remove from registry'
        ButtonOpenFolder          = 'Open folder'
        SectionJournal             = 'Log'
        ButtonCopyLog              = 'Copy'
        ButtonClearLog             = 'Clear'
        StatusReady                 = 'Ready.'
        MsgEnterClientName       = 'Enter a client name.'
        StatusBootstrapping      = "Bootstrapping '{0}'..."
        LogBootstrapHeader       = "== Bootstrap for '{0}' =="
        LogInteractiveRequired  = 'Interactive sign-in required (Global Admin / Application Administrator + Privileged Role Administrator).'
        LogFailed                    = 'FAILED: {0}'
        TitleBootstrapFailed     = 'Bootstrap failed'
        LogBootstrapDone          = "Bootstrap complete for '{0}'."
        MsgBootstrapReady        = "Client '{0}' ready. Use the 'Create waves' tab to start a deployment."
        TitleBootstrapDone       = 'Bootstrap complete'
        StatusParamsCopied       = 'Parameters copied to clipboard.'
        MsgSelectClient            = "Select a client ('Client registry' tab if the list is empty)."
        MsgEnterDeploymentName  = 'Enter a deployment name.'
        MsgAddWave                  = 'Add at least one wave.'
        MsgInvalidPercentage     = 'Invalid percentage for wave(s): {0}. Each value must be a whole number between 1 and 100.'
        TitleConfirmWaves        = 'Confirm wave creation'
        ConfirmWavesBody          = "Client: {0}`nType: {1}`nDeployment: {2}`nWaves: {3}%`n`nContinue?"
        StatusCreatingWaves      = "Creating waves for '{0}'..."
        LogWavesHeader             = '== Creating waves: {0} | {1} | {2} | {3}% =='
        TitleWavesFailed          = 'Wave creation failed'
        LogWavesDone               = 'Done. {0} group(s) created.'
        LogWaveRow                  = '  Wave {0} ({1}%) -> {2}: {3}/{4} member(s) added'
        MsgWavesDone               = '{0} group(s) created. See the Logs tab for details.'
        TitleDone                    = 'Done'
        MsgSelectClientList      = 'Select a client from the list.'
        TitleConfirm                = 'Confirm'
        ConfirmDeleteBody         = "Remove '{0}' from the local registry?`n`nThis does NOT delete the App Registration or the certificate in the tenant."
        LogClientRemoved          = "Client '{0}' removed from the local registry."
        AppReadyLog                 = 'IntuneWaveBuilder ready.'
        StatusCheckingModule     = 'Checking the Microsoft.Graph.Authentication module...'
        LogModuleWarning          = 'Warning: Microsoft.Graph.Authentication module unavailable ({0}).'
    }
    fr = @{
        AppSubtitle              = 'Vagues de deploiement Intune - groupes de securite Entra ID'
        RegistryCountFormat      = '{0} client(s) enregistre(s)'
        TabBootstrap              = 'Nouveau client (Bootstrap)'
        TabWaves                  = 'Creer des vagues'
        TabRegistry                = 'Registre clients'
        TabLogs                     = 'Logs'
        BootstrapSectionTitle    = 'App Registration dediee'
        BootstrapHint             = "A executer une seule fois par tenant client, connecte avec un compte Global Admin (ou Application Administrator + Privileged Role Administrator). Cree une App Registration isolee, un certificat local, et accorde le consentement admin pour les permissions minimales requises."
        LabelClientName          = 'Nom du client'
        TooltipClientName        = 'Nom court et unique, ex: Contoso'
        LabelCertYears            = 'Validite du certificat (annees)'
        ButtonBootstrapRun       = 'Se connecter et creer'
        HintBootstrapInteractive = "Une fenetre de connexion Microsoft s'ouvrira (authentification interactive)."
        SectionResult              = 'Resultat'
        ButtonCopyParams          = 'Copier les parametres'
        SectionParams              = 'Parametres'
        LabelClient                = 'Client'
        ButtonRefresh              = 'Actualiser'
        LabelTargetType           = 'Type de cible'
        RadioDevices                = 'Appareils'
        RadioUsers                  = 'Utilisateurs'
        LabelPlatform              = 'Plateforme (devices uniquement)'
        LabelDeploymentName      = 'Nom du deploiement'
        TooltipDeploymentName    = 'Utilise dans le nom des groupes de vague'
        SectionWaves               = 'Vagues'
        ColWave                      = 'Vague'
        ColPercentage              = 'Pourcentage'
        ButtonAddWave              = '+ Vague'
        ButtonRemoveWave         = '- Vague'
        WaveTotalFormat           = 'Total : {0}%'
        ButtonRunWaves             = 'Lancer la creation des vagues'
        SectionAbout               = 'A propos de cette operation'
        HintAbout1                  = "Le pool de selection est toujours restreint aux devices geres par Intune (managementState = managed). Chaque vague tire son pourcentage (calcule sur la taille du pool original) SANS REMISE : une entite deja assignee a une vague ne peut plus etre selectionnee par une vague suivante."
        HintAbout2                  = "Avant toute creation, le tenant reellement connecte (nom, domaine, TenantId) est affiche pour confirmation - protection contre un client mal selectionne."
        HintAbout3                  = "Un CSV par groupe (membres ajoutes / echecs) est ecrit dans le dossier Logs, consultable dans l'onglet Logs."
        HintRegistry                = "Reference locale uniquement (%LOCALAPPDATA%\IntuneWaveBuilder\clients.json). Supprimer une entree ici NE supprime PAS l'App Registration ni le certificat dans le tenant - cela retire seulement le raccourci local."
        ColClient                    = 'Client'
        ColCertThumb               = 'Empreinte du certificat'
        ColCreatedUtc              = 'Cree le (UTC)'
        ButtonDeleteRegistry     = 'Supprimer du registre'
        ButtonOpenFolder          = 'Ouvrir le dossier'
        SectionJournal             = 'Journal'
        ButtonCopyLog              = 'Copier'
        ButtonClearLog             = 'Effacer'
        StatusReady                 = 'Pret.'
        MsgEnterClientName       = 'Entre un nom de client.'
        StatusBootstrapping      = "Bootstrap en cours pour '{0}'..."
        LogBootstrapHeader       = "== Bootstrap pour '{0}' =="
        LogInteractiveRequired  = 'Connexion interactive requise (Global Admin / Application Administrator + Privileged Role Administrator).'
        LogFailed                    = 'ECHEC : {0}'
        TitleBootstrapFailed     = 'Bootstrap echoue'
        LogBootstrapDone          = "Bootstrap termine pour '{0}'."
        MsgBootstrapReady        = "Client '{0}' pret. Utilise l'onglet 'Creer des vagues' pour lancer un deploiement."
        TitleBootstrapDone       = 'Bootstrap termine'
        StatusParamsCopied       = 'Parametres copies dans le presse-papier.'
        MsgSelectClient            = "Selectionne un client (onglet 'Registre clients' si la liste est vide)."
        MsgEnterDeploymentName  = 'Entre un nom de deploiement.'
        MsgAddWave                  = 'Ajoute au moins une vague.'
        MsgInvalidPercentage     = 'Pourcentage invalide pour la/les vague(s) : {0}. Chaque valeur doit etre un entier entre 1 et 100.'
        TitleConfirmWaves        = 'Confirmer la creation des vagues'
        ConfirmWavesBody          = "Client : {0}`nType : {1}`nDeploiement : {2}`nVagues : {3}%`n`nContinuer ?"
        StatusCreatingWaves      = "Creation des vagues pour '{0}'..."
        LogWavesHeader             = '== Creation des vagues : {0} | {1} | {2} | {3}% =='
        TitleWavesFailed          = 'Creation des vagues echouee'
        LogWavesDone               = 'Termine. {0} groupe(s) cree(s).'
        LogWaveRow                  = '  Vague {0} ({1}%) -> {2} : {3}/{4} membre(s) ajoute(s)'
        MsgWavesDone               = "{0} groupe(s) cree(s). Voir l'onglet Logs pour le detail."
        TitleDone                    = 'Termine'
        MsgSelectClientList      = 'Selectionne un client dans la liste.'
        TitleConfirm                = 'Confirmer'
        ConfirmDeleteBody         = "Retirer '{0}' du registre local ?`n`nCeci ne supprime PAS l'App Registration ni le certificat dans le tenant."
        LogClientRemoved          = "Client '{0}' retire du registre local."
        AppReadyLog                 = 'IntuneWaveBuilder pret.'
        StatusCheckingModule     = 'Verification du module Microsoft.Graph.Authentication...'
        LogModuleWarning          = 'Avertissement : module Microsoft.Graph.Authentication indisponible ({0}).'
    }
}

function Get-WaveString {
    param([Parameter(Mandatory)][string]$Key, [object[]]$FormatArgs = @())
    $template = $script:Strings[$script:CurrentLang][$Key]
    if ($null -eq $template) { $template = $script:Strings['en'][$Key] }
    if ($FormatArgs.Count -gt 0) { return ($template -f $FormatArgs) }
    return $template
}

# ============================================================================
# State
# ============================================================================
$script:Busy = $false
$script:WaveRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$ctrl.WaveGrid.ItemsSource = $script:WaveRows

$LogsDir = Join-Path $ScriptDir 'Logs'

# ============================================================================
# Helpers (UI thread)
# ============================================================================
function Write-GuiLog {
    param([string]$Message, [string]$Color = 'Black')
    $ts = Get-Date -Format 'HH:mm:ss'
    $ctrl.LogBox.AppendText("[$ts] $Message`r`n")
    $ctrl.LogBox.ScrollToEnd()
}

function Set-Busy {
    param([bool]$Value, [string]$Message)
    $script:Busy = $Value
    foreach ($btn in @($ctrl.BootstrapRunButton, $ctrl.WaveRunButton, $ctrl.WaveClientRefreshButton,
                       $ctrl.RegistryRefreshButton, $ctrl.RegistryDeleteButton, $ctrl.RegistryCopyButton)) {
        $btn.IsEnabled = -not $Value
    }
    if ($Message) { $ctrl.StatusText.Text = $Message }
}

function ConvertTo-WaveInt {
    param($Value)
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-WaveRowsTotal {
    $sum = 0
    foreach ($row in $script:WaveRows) {
        $n = ConvertTo-WaveInt $row.Percentage
        if ($null -ne $n) { $sum += $n }
    }
    return $sum
}

function Update-WaveTotal {
    $sum = Get-WaveRowsTotal
    $ctrl.WaveTotalText.Text = Get-WaveString 'WaveTotalFormat' @($sum)
    $brushConverter = [System.Windows.Media.BrushConverter]::new()
    $ctrl.WaveTotalText.Foreground = if ($sum -eq 100) { $brushConverter.ConvertFromString('#B4A860') }
                                      elseif ($sum -gt 100) { $brushConverter.ConvertFromString('#C1554A') }
                                      else { $brushConverter.ConvertFromString('#93A19C') }
}

function Update-ClientCombos {
    $entries = @(Get-WaveClientRegistry)
    $ctrl.RegistryCountText.Text = Get-WaveString 'RegistryCountFormat' @($entries.Count)

    $selectedName = if ($ctrl.WaveClientCombo.SelectedItem) { $ctrl.WaveClientCombo.SelectedItem.ClientName } else { $null }
    $ctrl.WaveClientCombo.ItemsSource = $entries
    if ($selectedName) {
        $match = $entries | Where-Object { $_.ClientName -eq $selectedName }
        if ($match) { $ctrl.WaveClientCombo.SelectedItem = $match }
    }
    if (-not $ctrl.WaveClientCombo.SelectedItem -and $entries.Count -gt 0) { $ctrl.WaveClientCombo.SelectedIndex = 0 }

    $ctrl.RegistryGrid.ItemsSource = $entries
}

function Update-LogsFileList {
    $ctrl.LogsFileList.Items.Clear()
    if (Test-Path $LogsDir) {
        Get-ChildItem -Path $LogsDir -Filter '*.csv' | Sort-Object LastWriteTime -Descending | ForEach-Object {
            [void]$ctrl.LogsFileList.Items.Add($_.Name)
        }
    }
}

function New-WaveRow {
    $sum = Get-WaveRowsTotal
    $remaining = [Math]::Max(1, [Math]::Min(100, 100 - $sum))
    [pscustomobject]@{ Wave = $script:WaveRows.Count + 1; Percentage = $remaining }
}

function Update-WaveRowNumbers {
    for ($i = 0; $i -lt $script:WaveRows.Count; $i++) { $script:WaveRows[$i].Wave = $i + 1 }
    $ctrl.WaveGrid.Items.Refresh()
}

function Set-WaveLanguage {
    param([Parameter(Mandatory)][ValidateSet('en', 'fr')][string]$Lang)
    $script:CurrentLang = $Lang

    $ctrl.AppSubtitleText.Text = Get-WaveString 'AppSubtitle'
    $ctrl.TabBootstrap.Header = Get-WaveString 'TabBootstrap'
    $ctrl.TabWaves.Header = Get-WaveString 'TabWaves'
    $ctrl.TabRegistry.Header = Get-WaveString 'TabRegistry'
    $ctrl.TabLogs.Header = Get-WaveString 'TabLogs'

    $ctrl.BootstrapSectionTitle.Text = Get-WaveString 'BootstrapSectionTitle'
    $ctrl.BootstrapHint.Text = Get-WaveString 'BootstrapHint'
    $ctrl.LabelClientName.Content = Get-WaveString 'LabelClientName'
    $ctrl.BootstrapClientNameBox.ToolTip = Get-WaveString 'TooltipClientName'
    $ctrl.LabelCertYears.Content = Get-WaveString 'LabelCertYears'
    $ctrl.BootstrapRunButton.Content = Get-WaveString 'ButtonBootstrapRun'
    $ctrl.BootstrapInteractiveHint.Text = Get-WaveString 'HintBootstrapInteractive'
    $ctrl.ResultSectionTitle.Text = Get-WaveString 'SectionResult'
    $ctrl.BootstrapCopyButton.Content = Get-WaveString 'ButtonCopyParams'

    $ctrl.WavesSectionTitle.Text = Get-WaveString 'SectionParams'
    $ctrl.LabelClient.Content = Get-WaveString 'LabelClient'
    $ctrl.WaveClientRefreshButton.Content = Get-WaveString 'ButtonRefresh'
    $ctrl.LabelTargetType.Content = Get-WaveString 'LabelTargetType'
    $ctrl.TargetDeviceRadio.Content = Get-WaveString 'RadioDevices'
    $ctrl.TargetUserRadio.Content = Get-WaveString 'RadioUsers'
    $ctrl.LabelPlatform.Content = Get-WaveString 'LabelPlatform'
    $ctrl.LabelDeploymentName.Content = Get-WaveString 'LabelDeploymentName'
    $ctrl.DeploymentNameBox.ToolTip = Get-WaveString 'TooltipDeploymentName'
    $ctrl.WavesSectionTitle2.Text = Get-WaveString 'SectionWaves'
    $ctrl.WaveGrid.Columns[0].Header = Get-WaveString 'ColWave'
    $ctrl.WaveGrid.Columns[1].Header = Get-WaveString 'ColPercentage'
    $ctrl.WaveAddButton.Content = Get-WaveString 'ButtonAddWave'
    $ctrl.WaveRemoveButton.Content = Get-WaveString 'ButtonRemoveWave'
    $ctrl.WaveRunButton.Content = Get-WaveString 'ButtonRunWaves'
    $ctrl.AboutSectionTitle.Text = Get-WaveString 'SectionAbout'
    $ctrl.AboutHint1.Text = Get-WaveString 'HintAbout1'
    $ctrl.AboutHint2.Text = Get-WaveString 'HintAbout2'
    $ctrl.AboutHint3.Text = Get-WaveString 'HintAbout3'

    $ctrl.RegistryHint.Text = Get-WaveString 'HintRegistry'
    $ctrl.RegistryGrid.Columns[0].Header = Get-WaveString 'ColClient'
    $ctrl.RegistryGrid.Columns[3].Header = Get-WaveString 'ColCertThumb'
    $ctrl.RegistryGrid.Columns[4].Header = Get-WaveString 'ColCreatedUtc'
    $ctrl.RegistryRefreshButton.Content = Get-WaveString 'ButtonRefresh'
    $ctrl.RegistryCopyButton.Content = Get-WaveString 'ButtonCopyParams'
    $ctrl.RegistryDeleteButton.Content = Get-WaveString 'ButtonDeleteRegistry'

    $ctrl.LogsRefreshButton.Content = Get-WaveString 'ButtonRefresh'
    $ctrl.LogsOpenFolderButton.Content = Get-WaveString 'ButtonOpenFolder'

    $ctrl.JournalSectionTitle.Text = Get-WaveString 'SectionJournal'
    $ctrl.LogCopyButton.Content = Get-WaveString 'ButtonCopyLog'
    $ctrl.LogClearButton.Content = Get-WaveString 'ButtonClearLog'

    if (-not $script:Busy) { $ctrl.StatusText.Text = Get-WaveString 'StatusReady' }

    Update-ClientCombos
    Update-WaveTotal

    $brushConverter = [System.Windows.Media.BrushConverter]::new()
    $activeBrush = $brushConverter.ConvertFromString('#3A8571')
    $inactiveBrush = $brushConverter.ConvertFromString('#262A2E')
    $ctrl.LangFrButton.Background = if ($Lang -eq 'fr') { $activeBrush } else { $inactiveBrush }
    $ctrl.LangEnButton.Background = if ($Lang -eq 'en') { $activeBrush } else { $inactiveBrush }
}

# ============================================================================
# Background execution helper
# ============================================================================
# NOTE: a scriptblock invoked via '&' resolves variables/commands against the
# SessionState it was originally PARSED in, even when handed to another runspace
# (confirmed empirically) - so $Work is converted to text and re-parsed with
# [scriptblock]::Create() INSIDE the child runspace, which binds it to that
# runspace's SessionState and makes the dot-sourced Common.ps1 functions
# (Connect-WaveGraphApp, Invoke-NewWaveGroups, ...) resolvable. All external data
# the work needs must therefore be passed explicitly via -ArgumentList.
function Start-WaveBackgroundTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [Parameter(Mandatory)][scriptblock]$OnDone,
        [object[]]$ArgumentList = @()
    )

    $logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $workText = $Work.ToString()

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'MTA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('WaveWindow', $window)
    $runspace.SessionStateProxy.SetVariable('WaveScriptDir', $ScriptDir)
    $runspace.SessionStateProxy.SetVariable('WaveLogQueue', $logQueue)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({
        param($WorkText, $WorkArgs)

        . (Join-Path $WaveScriptDir 'WaveGroups.Common.ps1')

        function Write-WaveLogAsync {
            param([string]$Message)
            $WaveLogQueue.Enqueue($Message)
        }

        $result = $null
        $errorMessage = $null
        try {
            $work = [scriptblock]::Create($WorkText)
            $result = & $work @WorkArgs
        } catch {
            $errorMessage = $_.Exception.Message
        }
        [pscustomobject]@{ Result = $result; ErrorMessage = $errorMessage }
    }).AddArgument($workText).AddArgument($ArgumentList)

    $asyncResult = $ps.BeginInvoke()

    # NOTE: GetNewClosure() gives this Tick handler its own isolated SessionState -
    # captured VARIABLES ($logQueue, $logBox, ...) resolve fine, but calling a
    # top-level FUNCTION by name (e.g. Write-GuiLog) throws CommandNotFoundException,
    # because that isolated state has no knowledge of the script's function table.
    # So the log-draining logic is inlined here instead of calling Write-GuiLog.
    $logBox = $ctrl.LogBox
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $line = $null
        while ($logQueue.TryDequeue([ref]$line)) {
            $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $line`r`n")
            $logBox.ScrollToEnd()
        }
        if ($asyncResult.IsCompleted) {
            $timer.Stop()
            $line = $null
            while ($logQueue.TryDequeue([ref]$line)) {
                $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $line`r`n")
                $logBox.ScrollToEnd()
            }
            $output = $ps.EndInvoke($asyncResult)
            $ps.Dispose()
            $runspace.Dispose()
            $payload = $output | Select-Object -First 1
            & $OnDone $payload.Result $payload.ErrorMessage
        }
    }.GetNewClosure())
    $timer.Start()
}

# ============================================================================
# Event handlers - Language switcher
# ============================================================================
$ctrl.LangFrButton.Add_Click({ Set-WaveLanguage 'fr' })
$ctrl.LangEnButton.Add_Click({ Set-WaveLanguage 'en' })

# ============================================================================
# Event handlers - Bootstrap tab
# ============================================================================
$ctrl.BootstrapRunButton.Add_Click({
    if ($script:Busy) { return }
    $clientName = $ctrl.BootstrapClientNameBox.Text.Trim()
    if (-not $clientName) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgEnterClientName'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $certYearsItem = $ctrl.BootstrapCertYearsCombo.SelectedItem
    $certYears = if ($certYearsItem) { [int]$certYearsItem.Content } else { 2 }

    $ctrl.BootstrapResultTenantBox.Text = ''
    $ctrl.BootstrapResultClientBox.Text = ''
    $ctrl.BootstrapResultThumbBox.Text = ''
    $ctrl.BootstrapCopyButton.IsEnabled = $false

    Set-Busy $true (Get-WaveString 'StatusBootstrapping' @($clientName))
    Write-GuiLog (Get-WaveString 'LogBootstrapHeader' @($clientName))
    Write-GuiLog (Get-WaveString 'LogInteractiveRequired')

    Start-WaveBackgroundTask -ArgumentList @($clientName, $certYears) -Work {
        param($clientName, $certYears)
        Connect-WaveGraphInteractive -Scopes @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')
        $logSb = { param($Message, $Color) Write-WaveLogAsync -Message $Message }
        Invoke-TenantBootstrap -ClientName $clientName -CertValidityYears $certYears -Log $logSb
    } -OnDone {
        param($result, $err)
        Set-Busy $false (Get-WaveString 'StatusReady')
        if ($err) {
            Write-GuiLog (Get-WaveString 'LogFailed' @($err))
            [System.Windows.MessageBox]::Show($err, (Get-WaveString 'TitleBootstrapFailed'), 'OK', 'Error') | Out-Null
            return
        }
        Write-GuiLog (Get-WaveString 'LogBootstrapDone' @($result.ClientName))
        $ctrl.BootstrapResultTenantBox.Text = $result.TenantId
        $ctrl.BootstrapResultClientBox.Text = $result.ClientId
        $ctrl.BootstrapResultThumbBox.Text = $result.CertThumbprint
        $ctrl.BootstrapCopyButton.IsEnabled = $true
        Update-ClientCombos
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgBootstrapReady' @($result.ClientName)), (Get-WaveString 'TitleBootstrapDone'), 'OK', 'Information') | Out-Null
    }
})

$ctrl.BootstrapCopyButton.Add_Click({
    $text = "-TenantId '$($ctrl.BootstrapResultTenantBox.Text)' -ClientId '$($ctrl.BootstrapResultClientBox.Text)' -CertThumbprint '$($ctrl.BootstrapResultThumbBox.Text)'"
    [System.Windows.Clipboard]::SetText($text)
    $ctrl.StatusText.Text = Get-WaveString 'StatusParamsCopied'
})

# ============================================================================
# Event handlers - Create waves tab
# ============================================================================
$ctrl.WaveClientRefreshButton.Add_Click({ Update-ClientCombos })

$ctrl.TargetDeviceRadio.Add_Checked({ $ctrl.PlatformCombo.IsEnabled = $true })
$ctrl.TargetUserRadio.Add_Checked({ $ctrl.PlatformCombo.IsEnabled = $false })

$ctrl.WaveAddButton.Add_Click({
    $script:WaveRows.Add((New-WaveRow))
    Update-WaveTotal
})
$ctrl.WaveRemoveButton.Add_Click({
    $selected = $ctrl.WaveGrid.SelectedItem
    if ($selected) { $script:WaveRows.Remove($selected) | Out-Null }
    elseif ($script:WaveRows.Count -gt 0) { $script:WaveRows.RemoveAt($script:WaveRows.Count - 1) }
    Update-WaveRowNumbers
    Update-WaveTotal
})
$ctrl.WaveGrid.Add_CellEditEnding({
    # Deferred so the edited value has been committed to the bound object first.
    $ctrl.WaveGrid.Dispatcher.BeginInvoke([action]{ Update-WaveTotal }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
})

$ctrl.WaveRunButton.Add_Click({
    if ($script:Busy) { return }

    $client = $ctrl.WaveClientCombo.SelectedItem
    if (-not $client) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgSelectClient'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $deploymentName = $ctrl.DeploymentNameBox.Text.Trim()
    if (-not $deploymentName) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgEnterDeploymentName'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    if ($script:WaveRows.Count -eq 0) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgAddWave'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $percentages = [System.Collections.Generic.List[int]]::new()
    $invalidWaves = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $script:WaveRows.Count; $i++) {
        $n = ConvertTo-WaveInt $script:WaveRows[$i].Percentage
        if ($null -eq $n -or $n -lt 1 -or $n -gt 100) { $invalidWaves.Add($i + 1) }
        else { $percentages.Add($n) }
    }
    if ($invalidWaves.Count -gt 0) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgInvalidPercentage' @(($invalidWaves -join ', '))), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }

    $targetType = if ($ctrl.TargetDeviceRadio.IsChecked) { 'Device' } else { 'User' }
    $platformItem = $ctrl.PlatformCombo.SelectedItem
    $platform = if ($targetType -eq 'Device' -and $platformItem) { $platformItem.Content.ToString() } else { 'All' }

    $confirm = [System.Windows.MessageBox]::Show(
        (Get-WaveString 'ConfirmWavesBody' @($client.ClientName, $targetType, $deploymentName, ($percentages -join '%, '))),
        (Get-WaveString 'TitleConfirmWaves'), 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }

    Set-Busy $true (Get-WaveString 'StatusCreatingWaves' @($client.ClientName))
    Write-GuiLog (Get-WaveString 'LogWavesHeader' @($client.ClientName, $targetType, $deploymentName, ($percentages -join '%, ')))

    $tenantId = $client.TenantId
    $clientId = $client.ClientId
    $certThumb = $client.CertThumbprint
    $logDir = $LogsDir

    Start-WaveBackgroundTask -ArgumentList @($tenantId, $clientId, $certThumb, $targetType, $deploymentName, $platform, $percentages, $logDir) -Work {
        param($tenantId, $clientId, $certThumb, $targetType, $deploymentName, $platform, $percentages, $logDir)

        Connect-WaveGraphApp -TenantId $tenantId -ClientId $clientId -CertThumbprint $certThumb
        try {
            $orgInfo = Get-WaveOrganizationInfo -ExpectedTenantId $tenantId
            Write-WaveLogAsync -Message "Tenant connecte : $($orgInfo.DisplayName) ($($orgInfo.PrimaryDomain)) - $($orgInfo.Id)"
            if (-not $orgInfo.Matches) {
                throw "Le TenantId retourne par /organization ($($orgInfo.Id)) ne correspond pas au TenantId fourni ($tenantId). Abandon par securite."
            }

            $confirmed = $WaveWindow.Dispatcher.Invoke([Func[bool]]{
                $r = [System.Windows.MessageBox]::Show(
                    "Tenant connecte :`nNom : $($orgInfo.DisplayName)`nDomaine : $($orgInfo.PrimaryDomain)`nTenantId : $($orgInfo.Id)`n`nConfirmer la creation des groupes dans CE tenant ?",
                    'Confirmation du tenant', 'YesNo', 'Warning')
                return ($r -eq 'Yes')
            })
            if (-not $confirmed) { throw "Operation annulee par l'utilisateur (tenant non confirme)." }

            $logSb = { param($Message, $Color) Write-WaveLogAsync -Message $Message }
            Invoke-NewWaveGroups -TargetType $targetType -DeploymentName $deploymentName `
                -Platform $platform -WavePercentages $percentages -LogDir $logDir -Log $logSb
        } finally {
            Disconnect-MgGraph | Out-Null
        }
    } -OnDone {
        param($result, $err)
        Set-Busy $false (Get-WaveString 'StatusReady')
        if ($err) {
            Write-GuiLog (Get-WaveString 'LogFailed' @($err))
            [System.Windows.MessageBox]::Show($err, (Get-WaveString 'TitleWavesFailed'), 'OK', 'Error') | Out-Null
            return
        }
        Write-GuiLog (Get-WaveString 'LogWavesDone' @($result.Count))
        foreach ($row in $result) {
            Write-GuiLog (Get-WaveString 'LogWaveRow' @($row.Wave, $row.Percentage, $row.GroupName, $row.MembersAdded, $row.MembersTotal))
        }
        Update-LogsFileList
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgWavesDone' @($result.Count)), (Get-WaveString 'TitleDone'), 'OK', 'Information') | Out-Null
    }
})

# ============================================================================
# Event handlers - Registry tab
# ============================================================================
$ctrl.RegistryRefreshButton.Add_Click({ Update-ClientCombos })

$ctrl.RegistryCopyButton.Add_Click({
    $selected = $ctrl.RegistryGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgSelectClientList'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $text = "-TenantId '$($selected.TenantId)' -ClientId '$($selected.ClientId)' -CertThumbprint '$($selected.CertThumbprint)'"
    [System.Windows.Clipboard]::SetText($text)
    $ctrl.StatusText.Text = Get-WaveString 'StatusParamsCopied'
})

$ctrl.RegistryDeleteButton.Add_Click({
    $selected = $ctrl.RegistryGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show((Get-WaveString 'MsgSelectClientList'), 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $confirm = [System.Windows.MessageBox]::Show(
        (Get-WaveString 'ConfirmDeleteBody' @($selected.ClientName)),
        (Get-WaveString 'TitleConfirm'), 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    Remove-WaveClientEntry -ClientName $selected.ClientName
    Write-GuiLog (Get-WaveString 'LogClientRemoved' @($selected.ClientName))
    Update-ClientCombos
})

# ============================================================================
# Event handlers - Logs tab
# ============================================================================
$ctrl.LogsRefreshButton.Add_Click({ Update-LogsFileList })
$ctrl.LogsOpenFolderButton.Add_Click({
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
    Start-Process explorer.exe $LogsDir
})
$ctrl.LogsFileList.Add_SelectionChanged({
    $selectedFile = $ctrl.LogsFileList.SelectedItem
    if (-not $selectedFile) { return }
    $path = Join-Path $LogsDir $selectedFile
    if (Test-Path $path) {
        $ctrl.LogsContentGrid.ItemsSource = @(Import-Csv -Path $path)
    }
})

# ============================================================================
# Log panel handlers
# ============================================================================
$ctrl.LogCopyButton.Add_Click({ [System.Windows.Clipboard]::SetText($ctrl.LogBox.Text) })
$ctrl.LogClearButton.Add_Click({ $ctrl.LogBox.Clear() })

# ============================================================================
# Startup
# ============================================================================
$window.Add_Loaded({
    Set-WaveLanguage 'en'
    Write-GuiLog (Get-WaveString 'AppReadyLog')
    Update-ClientCombos
    Update-LogsFileList
    $script:WaveRows.Add((New-WaveRow))
    Update-WaveTotal

    Set-Busy $true (Get-WaveString 'StatusCheckingModule')
    Start-WaveBackgroundTask -Work {
        Assert-WaveGraphAuthModule
        'ok'
    } -OnDone {
        param($result, $err)
        Set-Busy $false (Get-WaveString 'StatusReady')
        if ($err) { Write-GuiLog (Get-WaveString 'LogModuleWarning' @($err)) }
    }
})

[void]$window.ShowDialog()
