<#
.SYNOPSIS
    Interface graphique (WPF) pour IntuneWaveBuilder : bootstrap d'un nouveau client,
    creation de vagues de deploiement, registre des clients enregistres et consultation
    des logs de creation.

.DESCRIPTION
    Pilote les memes fonctions que les scripts en ligne de commande (Bootstrap-TenantApp.ps1,
    New-WaveGroups.ps1), via la logique partagee de WaveGroups.Common.ps1
    (Invoke-TenantBootstrap, Invoke-NewWaveGroups). Aucune duplication de logique Graph.

    Les operations reseau (Graph) s'executent dans un runspace de fond pour ne pas geler
    la fenetre ; les mises a jour d'interface sont marshalees sur le thread UI via le
    Dispatcher de la fenetre.

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
                    <TextBlock Text="Vagues de deploiement Intune - groupes de securite Entra ID" Foreground="{StaticResource TextSecondaryBrush}"/>
                </StackPanel>
                <TextBlock x:Name="RegistryCountText" Text="0 client(s) enregistre(s)" Foreground="{StaticResource TextSecondaryBrush}"
                           HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="1" Margin="0">

            <!-- Tab 1: Bootstrap -->
            <TabItem Header="Nouveau client (Bootstrap)">
              <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0">
                        <TextBlock Text="App Registration dediee" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Style="{StaticResource HintText}" Text="A executer une seule fois par tenant client, connecte avec un compte Global Admin (ou Application Administrator + Privileged Role Administrator). Cree une App Registration isolee, un certificat local, et accorde le consentement admin pour les permissions minimales requises."/>

                        <Label Content="Nom du client"/>
                        <TextBox x:Name="BootstrapClientNameBox" ToolTip="Nom court et unique, ex: Contoso"/>

                        <Label Content="Validite du certificat (annees)"/>
                        <ComboBox x:Name="BootstrapCertYearsCombo" SelectedIndex="1">
                            <ComboBoxItem Content="1"/>
                            <ComboBoxItem Content="2"/>
                            <ComboBoxItem Content="3"/>
                            <ComboBoxItem Content="5"/>
                            <ComboBoxItem Content="10"/>
                        </ComboBox>

                        <Button x:Name="BootstrapRunButton" Content="Se connecter et creer" Margin="0,16,0,0" HorizontalAlignment="Left"/>
                        <TextBlock Style="{StaticResource HintText}" Margin="0,8,0,0" Text="Une fenetre de connexion Microsoft s'ouvrira (authentification interactive)."/>
                    </StackPanel>

                    <StackPanel Grid.Column="2">
                        <TextBlock Text="Resultat" Style="{StaticResource SectionTitle}"/>
                        <Label Content="TenantId"/>
                        <TextBox x:Name="BootstrapResultTenantBox" IsReadOnly="True"/>
                        <Label Content="ClientId"/>
                        <TextBox x:Name="BootstrapResultClientBox" IsReadOnly="True"/>
                        <Label Content="Certificate Thumbprint"/>
                        <TextBox x:Name="BootstrapResultThumbBox" IsReadOnly="True"/>
                        <Button x:Name="BootstrapCopyButton" Content="Copier les parametres" Style="{StaticResource SecondaryButton}" Margin="0,12,0,0" HorizontalAlignment="Left" IsEnabled="False"/>
                    </StackPanel>
                </Grid>
              </ScrollViewer>
            </TabItem>

            <!-- Tab 2: Create waves -->
            <TabItem Header="Creer des vagues">
              <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="360"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0">
                        <TextBlock Text="Parametres" Style="{StaticResource SectionTitle}"/>

                        <Label Content="Client"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox x:Name="WaveClientCombo" Grid.Column="0" DisplayMemberPath="ClientName"/>
                            <Button x:Name="WaveClientRefreshButton" Grid.Column="1" Content="Actualiser" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                        </Grid>

                        <Label Content="Type de cible"/>
                        <StackPanel Orientation="Horizontal">
                            <RadioButton x:Name="TargetDeviceRadio" Content="Devices" GroupName="TargetType" IsChecked="True" VerticalAlignment="Center" Margin="0,0,20,0"/>
                            <RadioButton x:Name="TargetUserRadio" Content="Users" GroupName="TargetType" VerticalAlignment="Center"/>
                        </StackPanel>

                        <Label Content="Plateforme (devices uniquement)"/>
                        <ComboBox x:Name="PlatformCombo" SelectedIndex="0">
                            <ComboBoxItem Content="All"/>
                            <ComboBoxItem Content="Windows"/>
                            <ComboBoxItem Content="iOS"/>
                            <ComboBoxItem Content="Android"/>
                            <ComboBoxItem Content="Linux"/>
                            <ComboBoxItem Content="macOS"/>
                        </ComboBox>

                        <Label Content="Nom du deploiement"/>
                        <TextBox x:Name="DeploymentNameBox" ToolTip="Utilise dans le nom des groupes de vague"/>

                        <TextBlock Text="Vagues" Style="{StaticResource SectionTitle}" Margin="0,16,0,8"/>
                        <DataGrid x:Name="WaveGrid" Height="180" AutoGenerateColumns="False" CanUserAddRows="False"
                                  CanUserDeleteRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Vague" Binding="{Binding Wave}" IsReadOnly="True" Width="70"/>
                                <DataGridTextColumn Header="Pourcentage" Binding="{Binding Percentage}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>
                        <Grid Margin="0,8,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="WaveAddButton" Grid.Column="0" Content="+ Vague" Style="{StaticResource SecondaryButton}"/>
                            <Button x:Name="WaveRemoveButton" Grid.Column="1" Content="- Vague" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                            <TextBlock x:Name="WaveTotalText" Grid.Column="2" Text="Total : 0%" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="{StaticResource TextSecondaryBrush}"/>
                        </Grid>

                        <Button x:Name="WaveRunButton" Content="Lancer la creation des vagues" Margin="0,20,0,20" HorizontalAlignment="Left"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2">
                        <TextBlock Text="A propos de cette operation" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Style="{StaticResource HintText}" Text="Le pool de selection est toujours restreint aux devices geres par Intune (managementState = managed). Chaque vague tire son pourcentage (calcule sur la taille du pool original) SANS REMISE : une entite deja assignee a une vague ne peut plus etre selectionnee par une vague suivante."/>
                        <TextBlock Style="{StaticResource HintText}" Text="Avant toute creation, le tenant reellement connecte (nom, domaine, TenantId) est affiche pour confirmation - protection contre un client mal selectionne."/>
                        <TextBlock Style="{StaticResource HintText}" Text="Un CSV par groupe (membres ajoutes / echecs) est ecrit dans le dossier Logs, consultable dans l'onglet Logs."/>
                    </StackPanel>
                </Grid>
              </ScrollViewer>
            </TabItem>

            <!-- Tab 3: Client registry -->
            <TabItem Header="Registre clients">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Style="{StaticResource HintText}" Text="Reference locale uniquement (%LOCALAPPDATA%\IntuneWaveBuilder\clients.json). Supprimer une entree ici NE supprime PAS l'App Registration ni le certificat dans le tenant - cela retire seulement le raccourci local."/>

                    <DataGrid x:Name="RegistryGrid" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True"
                              HeadersVisibility="Column" GridLinesVisibility="Horizontal" SelectionMode="Single">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Client" Binding="{Binding ClientName}" Width="160"/>
                            <DataGridTextColumn Header="TenantId" Binding="{Binding TenantId}" Width="260"/>
                            <DataGridTextColumn Header="ClientId" Binding="{Binding ClientId}" Width="260"/>
                            <DataGridTextColumn Header="Certificate Thumbprint" Binding="{Binding CertThumbprint}" Width="220"/>
                            <DataGridTextColumn Header="Cree le (UTC)" Binding="{Binding CreatedUtc}" Width="*"/>
                        </DataGrid.Columns>
                    </DataGrid>

                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button x:Name="RegistryRefreshButton" Content="Actualiser" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="RegistryCopyButton" Content="Copier les parametres" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
                        <Button x:Name="RegistryDeleteButton" Content="Supprimer du registre" Style="{StaticResource DangerButton}" Margin="8,0,0,0"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- Tab 4: Logs -->
            <TabItem Header="Logs">
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
                        <Button x:Name="LogsRefreshButton" Content="Actualiser" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="LogsOpenFolderButton" Content="Ouvrir le dossier" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
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
                    <TextBlock Text="Journal" Style="{StaticResource SectionTitle}" Margin="0,0,0,6"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button x:Name="LogCopyButton" Content="Copier" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="LogClearButton" Content="Effacer" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0"/>
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
            <TextBlock x:Name="StatusText" Text="Pret." Foreground="{StaticResource TextSecondaryBrush}"/>
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
    'RegistryCountText',
    'BootstrapClientNameBox','BootstrapCertYearsCombo','BootstrapRunButton',
    'BootstrapResultTenantBox','BootstrapResultClientBox','BootstrapResultThumbBox','BootstrapCopyButton',
    'WaveClientCombo','WaveClientRefreshButton','TargetDeviceRadio','TargetUserRadio','PlatformCombo',
    'DeploymentNameBox','WaveGrid','WaveAddButton','WaveRemoveButton','WaveTotalText','WaveRunButton',
    'RegistryGrid','RegistryRefreshButton','RegistryCopyButton','RegistryDeleteButton',
    'LogsRefreshButton','LogsOpenFolderButton','LogsFileList','LogsContentGrid',
    'LogBox','LogCopyButton','LogClearButton','StatusText'
)
$ctrl = @{}
foreach ($name in $controlNames) { $ctrl[$name] = $window.FindName($name) }

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

function Update-WaveTotal {
    $sum = 0
    foreach ($row in $script:WaveRows) { $sum += [int]$row.Percentage }
    $ctrl.WaveTotalText.Text = "Total : $sum%"
    $brushConverter = [System.Windows.Media.BrushConverter]::new()
    $ctrl.WaveTotalText.Foreground = if ($sum -eq 100) { $brushConverter.ConvertFromString('#B4A860') }
                                      elseif ($sum -gt 100) { $brushConverter.ConvertFromString('#C1554A') }
                                      else { $brushConverter.ConvertFromString('#93A19C') }
}

function Update-ClientCombos {
    $entries = @(Get-WaveClientRegistry)
    $ctrl.RegistryCountText.Text = "$($entries.Count) client(s) enregistre(s)"

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
    $sum = 0
    foreach ($row in $script:WaveRows) { $sum += [int]$row.Percentage }
    $remaining = [Math]::Max(1, [Math]::Min(100, 100 - $sum))
    [pscustomobject]@{ Wave = $script:WaveRows.Count + 1; Percentage = $remaining }
}

function Update-WaveRowNumbers {
    for ($i = 0; $i -lt $script:WaveRows.Count; $i++) { $script:WaveRows[$i].Wave = $i + 1 }
    $ctrl.WaveGrid.Items.Refresh()
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
# Event handlers - Bootstrap tab
# ============================================================================
$ctrl.BootstrapRunButton.Add_Click({
    if ($script:Busy) { return }
    $clientName = $ctrl.BootstrapClientNameBox.Text.Trim()
    if (-not $clientName) {
        [System.Windows.MessageBox]::Show('Entre un nom de client.', 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $certYearsItem = $ctrl.BootstrapCertYearsCombo.SelectedItem
    $certYears = if ($certYearsItem) { [int]$certYearsItem.Content } else { 2 }

    $ctrl.BootstrapResultTenantBox.Text = ''
    $ctrl.BootstrapResultClientBox.Text = ''
    $ctrl.BootstrapResultThumbBox.Text = ''
    $ctrl.BootstrapCopyButton.IsEnabled = $false

    Set-Busy $true "Bootstrap en cours pour '$clientName'..."
    Write-GuiLog "== Bootstrap pour '$clientName' =="
    Write-GuiLog "Connexion interactive requise (Global Admin / Application Administrator + Privileged Role Administrator)."

    Start-WaveBackgroundTask -ArgumentList @($clientName, $certYears) -Work {
        param($clientName, $certYears)
        Connect-WaveGraphInteractive -Scopes @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')
        $logSb = { param($Message, $Color) Write-WaveLogAsync -Message $Message }
        Invoke-TenantBootstrap -ClientName $clientName -CertValidityYears $certYears -Log $logSb
    } -OnDone {
        param($result, $err)
        Set-Busy $false 'Pret.'
        if ($err) {
            Write-GuiLog "ECHEC : $err"
            [System.Windows.MessageBox]::Show($err, 'Bootstrap echoue', 'OK', 'Error') | Out-Null
            return
        }
        Write-GuiLog "Bootstrap termine pour '$($result.ClientName)'."
        $ctrl.BootstrapResultTenantBox.Text = $result.TenantId
        $ctrl.BootstrapResultClientBox.Text = $result.ClientId
        $ctrl.BootstrapResultThumbBox.Text = $result.CertThumbprint
        $ctrl.BootstrapCopyButton.IsEnabled = $true
        Update-ClientCombos
        [System.Windows.MessageBox]::Show("Client '$($result.ClientName)' pret. Utilise l'onglet 'Creer des vagues' pour lancer un deploiement.", 'Bootstrap termine', 'OK', 'Information') | Out-Null
    }
})

$ctrl.BootstrapCopyButton.Add_Click({
    $text = "-TenantId '$($ctrl.BootstrapResultTenantBox.Text)' -ClientId '$($ctrl.BootstrapResultClientBox.Text)' -CertThumbprint '$($ctrl.BootstrapResultThumbBox.Text)'"
    [System.Windows.Clipboard]::SetText($text)
    $ctrl.StatusText.Text = 'Parametres copies dans le presse-papier.'
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
        [System.Windows.MessageBox]::Show("Selectionne un client (onglet 'Registre clients' si la liste est vide).", 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $deploymentName = $ctrl.DeploymentNameBox.Text.Trim()
    if (-not $deploymentName) {
        [System.Windows.MessageBox]::Show('Entre un nom de deploiement.', 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    if ($script:WaveRows.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Ajoute au moins une vague.", 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $percentages = @($script:WaveRows | ForEach-Object { [int]$_.Percentage })
    if ($percentages | Where-Object { $_ -lt 1 -or $_ -gt 100 }) {
        [System.Windows.MessageBox]::Show('Chaque pourcentage de vague doit etre entre 1 et 100.', 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }

    $targetType = if ($ctrl.TargetDeviceRadio.IsChecked) { 'Device' } else { 'User' }
    $platformItem = $ctrl.PlatformCombo.SelectedItem
    $platform = if ($targetType -eq 'Device' -and $platformItem) { $platformItem.Content.ToString() } else { 'All' }

    $confirm = [System.Windows.MessageBox]::Show(
        "Client : $($client.ClientName)`nType : $targetType`nDeploiement : $deploymentName`nVagues : $($percentages -join '%, ')%`n`nContinuer ?",
        'Confirmer la creation des vagues', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }

    Set-Busy $true "Creation des vagues pour '$($client.ClientName)'..."
    Write-GuiLog "== Creation des vagues : $($client.ClientName) | $targetType | $deploymentName | $($percentages -join '%, ')% =="

    $tenantId = $client.TenantId
    $clientId = $client.ClientId
    $certThumb = $client.CertThumbprint
    $logDir = $LogsDir

    Start-WaveBackgroundTask -ArgumentList @($tenantId, $clientId, $certThumb, $targetType, $deploymentName, $platform, $percentages, $logDir) -Work {
        param($tenantId, $clientId, $certThumb, $targetType, $deploymentName, $platform, $percentages, $logDir)

        Connect-WaveGraphApp -TenantId $tenantId -ClientId $clientId -CertThumbprint $certThumb
        $orgInfo = Get-WaveOrganizationInfo -ExpectedTenantId $tenantId
        Write-WaveLogAsync -Message "Tenant connecte : $($orgInfo.DisplayName) ($($orgInfo.PrimaryDomain)) - $($orgInfo.Id)"

        $confirmed = $WaveWindow.Dispatcher.Invoke([Func[bool]]{
            $r = [System.Windows.MessageBox]::Show(
                "Tenant connecte :`nNom : $($orgInfo.DisplayName)`nDomaine : $($orgInfo.PrimaryDomain)`nTenantId : $($orgInfo.Id)`n`nConfirmer la creation des groupes dans CE tenant ?",
                'Confirmation du tenant', 'YesNo', 'Warning')
            return ($r -eq 'Yes')
        })
        if (-not $confirmed) { Disconnect-MgGraph | Out-Null; throw "Operation annulee par l'utilisateur (tenant non confirme)." }

        $logSb = { param($Message, $Color) Write-WaveLogAsync -Message $Message }
        $summary = Invoke-NewWaveGroups -TargetType $targetType -DeploymentName $deploymentName `
            -Platform $platform -WavePercentages $percentages -LogDir $logDir -Log $logSb
        Disconnect-MgGraph | Out-Null
        $summary
    } -OnDone {
        param($result, $err)
        Set-Busy $false 'Pret.'
        if ($err) {
            Write-GuiLog "ECHEC : $err"
            [System.Windows.MessageBox]::Show($err, 'Creation des vagues echouee', 'OK', 'Error') | Out-Null
            return
        }
        Write-GuiLog "Termine. $($result.Count) groupe(s) cree(s)."
        foreach ($row in $result) {
            Write-GuiLog "  Vague $($row.Wave) ($($row.Percentage)%) -> $($row.GroupName) : $($row.MembersAdded)/$($row.MembersTotal) membre(s) ajoute(s)"
        }
        Update-LogsFileList
        [System.Windows.MessageBox]::Show("$($result.Count) groupe(s) cree(s). Voir l'onglet Logs pour le detail.", 'Termine', 'OK', 'Information') | Out-Null
    }
})

# ============================================================================
# Event handlers - Registry tab
# ============================================================================
$ctrl.RegistryRefreshButton.Add_Click({ Update-ClientCombos })

$ctrl.RegistryCopyButton.Add_Click({
    $selected = $ctrl.RegistryGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Selectionne un client dans la liste.', 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $text = "-TenantId '$($selected.TenantId)' -ClientId '$($selected.ClientId)' -CertThumbprint '$($selected.CertThumbprint)'"
    [System.Windows.Clipboard]::SetText($text)
    $ctrl.StatusText.Text = 'Parametres copies dans le presse-papier.'
})

$ctrl.RegistryDeleteButton.Add_Click({
    $selected = $ctrl.RegistryGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Selectionne un client dans la liste.', 'IntuneWaveBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    $confirm = [System.Windows.MessageBox]::Show(
        "Retirer '$($selected.ClientName)' du registre local ?`n`nCeci ne supprime PAS l'App Registration ni le certificat dans le tenant.",
        'Confirmer', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    Remove-WaveClientEntry -ClientName $selected.ClientName
    Write-GuiLog "Client '$($selected.ClientName)' retire du registre local."
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
    Write-GuiLog 'IntuneWaveBuilder pret.'
    Update-ClientCombos
    Update-LogsFileList
    $script:WaveRows.Add((New-WaveRow))
    Update-WaveTotal

    Start-WaveBackgroundTask -Work {
        Assert-WaveGraphAuthModule
        'ok'
    } -OnDone {
        param($result, $err)
        if ($err) { Write-GuiLog "Avertissement : module Microsoft.Graph.Authentication indisponible ($err)." }
    }
})

[void]$window.ShowDialog()
