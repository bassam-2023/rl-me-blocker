# =====================================================================
#  RL-ME-Blocker.ps1
#  Toggle blocking of Rocket League's Middle East (ME6) servers via
#  Windows Firewall. Self-elevates once on launch. English + Arabic.
#  https://github.com/bassam-2023/rl-me-blocker
# =====================================================================

$AppVersion = '1.0.0'
$RepoUrl    = 'https://github.com/bassam-2023/rl-me-blocker'
$RemoteUrl  = 'https://raw.githubusercontent.com/bassam-2023/rl-me-blocker/main/ranges.json'

# ---- Self-elevate to Administrator (and make sure we're STA for WPF) ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $argList = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    try {
        if ($isAdmin) { Start-Process powershell.exe $argList }
        else          { Start-Process powershell.exe $argList -Verb RunAs }
    } catch { }   # UAC declined
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Our own AppUserModelID gives the window its own taskbar button (showing the live status
# icon) instead of grouping it under PowerShell. Has to happen before the window exists.
try {
    if (-not ('RLBlockME.Native' -as [type])) {
        Add-Type -Namespace RLBlockME -Name Native -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern void SHChangeNotify(int eventId, int flags, string item1, IntPtr item2);
'@
    }
    [void][RLBlockME.Native]::SetCurrentProcessExplicitAppUserModelID('RLBlockME.MEBlocker')
} catch { }

$Group = 'RL-Block-ME'
$RuleDefs = @(
    @{ DisplayName = 'RL-Block-ME (Outbound)'; Direction = 'Outbound' },
    @{ DisplayName = 'RL-Block-ME (Inbound)';  Direction = 'Inbound'  }
)

# Status icons: generated .ico files live next to the script, and any Desktop / Start menu
# shortcut that launches this exact file gets the icon of the current state.
$IconDir      = Join-Path $PSScriptRoot 'icons'
$ShortcutDirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                  [Environment]::GetFolderPath('Programs'))
$AppScript    = $PSCommandPath
$RangesFile   = Join-Path $PSScriptRoot 'ranges.json'     # last list downloaded from GitHub
$SettingsFile = Join-Path $PSScriptRoot 'settings.json'   # remembered language

function Read-JsonFile([string]$path) {
    try {
        if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    } catch { }
    $null
}

# ---- ME6 address ranges -----------------------------------------------
# Built-in list, replaced by the cached/online copy of ranges.json when that one is valid.
# The online list is only ever used to decide which addresses to BLOCK, so it's checked
# strictly: plain IPv4 CIDRs, nothing wider than a /8.
$Cidrs = @('34.164.0.0/16', '34.165.0.0/16', '35.252.0.0/16')

function Test-Cidrs($list) {
    $list = @($list)
    if ($list.Count -lt 1 -or $list.Count -gt 64) { return $false }
    foreach ($c in $list) {
        if ($c -isnot [string] -or $c -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$') { return $false }
        if ([int]$Matches[5] -lt 8 -or [int]$Matches[5] -gt 32) { return $false }
        foreach ($i in 1..4) { if ([int]$Matches[$i] -gt 255) { return $false } }
    }
    $true
}

# Windows reports rule addresses as "34.164.0.0/255.255.0.0", so compare in one form
function ConvertTo-CidrKey([string]$addr) {
    $ip, $mask = $addr -split '/', 2
    if (-not $mask) { $mask = '32' }
    if ($mask -like '*.*') {
        $bits = -join ([Net.IPAddress]::Parse($mask).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2) })
        $mask = ($bits -replace '0').Length
    }
    "$ip/$mask"
}

function Get-RangesKey($list) { (@($list | ForEach-Object { ConvertTo-CidrKey $_ }) | Sort-Object) -join ',' }

$cached = Read-JsonFile $RangesFile
if ($cached -and (Test-Cidrs $cached.ranges)) { $Cidrs = @($cached.ranges) }

# ---- Language -----------------------------------------------------------
$Strings = @{
    en = @{
        WindowTitle = 'RL ME Blocker'
        AppName     = 'ME BLOCKER'
        OtherLang   = [string][char]0x0639   # the Arabic letter 'ain' - switches to Arabic
        LangTip     = 'العربية'
        OnTitle     = 'BLOCKED';  OnSub      = "Rocket League can't reach Middle East servers."
        OffTitle    = 'ALLOWED';  OffSub     = 'Rocket League can connect to Middle East servers.'
        PartialTitle = 'PARTIAL'; PartialSub = 'Only one direction is blocked. Choose Allow or Block to fix it.'
        MissingTitle = 'NO RULES'; MissingSub = 'The firewall rules are missing. Choose Block to recreate them.'
        Allow       = 'Allow';    Block      = 'Block'
        Blocking    = 'Blocking Middle East servers...'
        Allowing    = 'Allowing Middle East servers...'
        RangesHeader = 'ME6 SERVER RANGES'
        Outbound    = 'Outbound'; Inbound    = 'Inbound'
        RuleOn      = 'Blocking'; RuleOff    = 'Open'
        SyncNote    = "Windows didn't save this to disk, so it may reset after a restart. If it does, just switch it again."
        Hint        = 'Switch before you queue - the server is picked at match start.'
        ErrPrepare  = "Couldn't prepare firewall rules: {0}"
        ErrRead     = "Couldn't read firewall state: {0}"
        ErrApply    = "Windows Firewall didn't apply the change. Try again, or restart the app."
        WarnThirdParty = '{0} is managing your firewall, so this block may not work. Use its own settings, or turn Windows Firewall back on.'
        WarnOff     = 'Windows Firewall is turned off for this network, so blocking has no effect. Turn it on in Windows Security > Firewall.'
        Update      = 'Update available: v{0} - click to download'
    }
    ar = @{
        WindowTitle = 'حاجب سيرفرات ME'
        AppName     = 'حاجب سيرفرات ME'
        OtherLang   = 'EN'
        LangTip     = 'English'
        OnTitle     = 'محظور';  OnSub      = 'اللعبة لا تستطيع الاتصال بسيرفرات الشرق الأوسط.'
        OffTitle    = 'مسموح';  OffSub     = 'اللعبة تستطيع الاتصال بسيرفرات الشرق الأوسط.'
        PartialTitle = 'جزئي';   PartialSub = 'الحظر مفعّل في اتجاه واحد فقط. اختر سماح أو حظر لإصلاحه.'
        MissingTitle = 'لا توجد قواعد'; MissingSub = 'قواعد الجدار الناري مفقودة. اختر حظر لإعادة إنشائها.'
        Allow       = 'سماح';   Block      = 'حظر'
        Blocking    = 'جارٍ حظر سيرفرات الشرق الأوسط...'
        Allowing    = 'جارٍ السماح بسيرفرات الشرق الأوسط...'
        RangesHeader = 'نطاقات سيرفرات ME6'
        Outbound    = 'الصادر'; Inbound    = 'الوارد'
        RuleOn      = 'محظور';  RuleOff    = 'مفتوح'
        SyncNote    = 'لم يحفظ ويندوز هذا التغيير، لذلك قد يرجع بعد إعادة تشغيل الجهاز. إذا حصل ذلك، بدّل مرة أخرى.'
        Hint        = 'بدّل قبل البحث عن مباراة - السيرفر يُحدَّد عند بداية المباراة.'
        ErrPrepare  = 'تعذّر تجهيز قواعد الجدار الناري: {0}'
        ErrRead     = 'تعذّرت قراءة حالة الجدار الناري: {0}'
        ErrApply    = 'لم يطبّق جدار حماية ويندوز التغيير. حاول مرة أخرى أو أعد تشغيل البرنامج.'
        WarnThirdParty = 'برنامج {0} يتحكم في الجدار الناري، لذلك قد لا يعمل الحظر. استخدم إعداداته، أو أعد تشغيل جدار حماية ويندوز.'
        WarnOff     = 'جدار حماية ويندوز متوقف على هذه الشبكة، لذلك الحظر لن يعمل. شغّله من أمان Windows > جدار الحماية.'
        Update      = 'يتوفر تحديث: v{0} - اضغط للتحميل'
    }
}

$settings = Read-JsonFile $SettingsFile
$script:Lang = if ($settings -and $settings.lang -in 'en', 'ar') { $settings.lang }
               elseif ((Get-UICulture).TwoLetterISOLanguageName -eq 'ar') { 'ar' }
               else { 'en' }

function L([string]$key) { $Strings[$script:Lang][$key] }

# ---- Firewall logic -------------------------------------------------
# Windows keeps two copies of each rule: the saved one (PersistentStore) and
# the one actually being enforced (ActiveStore). They can disagree, so the UI
# always shows what's enforced and every change is verified against it.

function Ensure-Rules {
    $want = Get-RangesKey $Cidrs
    foreach ($def in $RuleDefs) {
        $existing = @(Get-NetFirewallRule -DisplayName $def.DisplayName -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
        if ($existing.Count -eq 0) {
            New-NetFirewallRule -DisplayName $def.DisplayName -Group $Group -Direction $def.Direction `
                -Action Block -RemoteAddress $Cidrs -Enabled False -Profile Any -PolicyStore PersistentStore | Out-Null
            continue
        }
        # Keep existing rules on the current ME6 list (it can change online)
        foreach ($r in $existing) {
            $have = Get-RangesKey @(($r | Get-NetFirewallAddressFilter).RemoteAddress)
            if ($have -ne $want) { $r | Set-NetFirewallRule -RemoteAddress $Cidrs -ErrorAction Stop }
        }
    }
}

function Get-BlockState {
    $rules = @(Get-NetFirewallRule -Group $Group -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $on    = @($rules | Where-Object { $_.Enabled -eq 'True' })
    $saved = @(Get-NetFirewallRule -Group $Group -PolicyStore PersistentStore -ErrorAction SilentlyContinue |
               Where-Object { $_.Enabled -eq 'True' })
    $status = if ($rules.Count -eq 0) { 'Missing' }
              elseif ($on.Count -eq $rules.Count) { 'On' }
              elseif ($on.Count -eq 0) { 'Off' }
              else { 'Partial' }
    [pscustomobject]@{
        Status   = $status
        Inbound  = @($on | Where-Object { $_.Direction -eq 'Inbound' }).Count -gt 0
        Outbound = @($on | Where-Object { $_.Direction -eq 'Outbound' }).Count -gt 0
        Saved    = $saved.Count -eq $on.Count   # $false: Windows didn't write it to disk, may reset on reboot
    }
}

function Set-BlockState([bool]$On) {
    Ensure-Rules
    $flag = if ($On) { 'True' } else { 'False' }
    $want = if ($On) { 'On' } else { 'Off' }
    Set-NetFirewallRule -Group $Group -PolicyStore PersistentStore -Enabled $flag -ErrorAction Stop
    if ((Get-BlockState).Status -ne $want) { throw (L 'ErrApply') }
}

# The rules only matter if Windows Firewall is the one enforcing them on the current network.
# Returns a warning to show, or $null when everything is fine.
function Get-FirewallWarning {
    try {
        $third = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -ErrorAction Stop |
                   Where-Object { (($_.productState -shr 12) -band 0xF) -eq 1 })   # third-party firewall switched on
        if ($third.Count) { return (L 'WarnThirdParty') -f $third[0].displayName }
    } catch { }
    try {
        if ((Get-Service MpsSvc -ErrorAction Stop).Status -ne 'Running') { return L 'WarnOff' }
        $map = @{ Public = 'Public'; Private = 'Private'; DomainAuthenticated = 'Domain' }
        $names = @(Get-NetConnectionProfile -ErrorAction Stop | ForEach-Object { $map["$($_.NetworkCategory)"] } | Where-Object { $_ })
        if ($names.Count -eq 0) { $names = 'Domain', 'Private', 'Public' }
        $off = @(Get-NetFirewallProfile -PolicyStore ActiveStore -Name $names -ErrorAction Stop | Where-Object { "$($_.Enabled)" -ne 'True' })
        if ($off.Count) { return L 'WarnOff' }
    } catch { }
    $null
}

# ---- UI ---------------------------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RL ME Blocker" Width="420" SizeToContent="Height" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanMinimize"
        FontFamily="Segoe UI" SnapsToDevicePixels="True" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="#8A96AD"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="8" Width="34" Height="30">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#222B40"/>
                <Setter Property="Foreground" Value="#EAF0FA"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Seg" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="Root" Margin="16">
    <Border CornerRadius="18" Background="#0E131F">
      <Border.Effect><DropShadowEffect BlurRadius="22" ShadowDepth="0" Opacity="0.55" Color="#000000"/></Border.Effect>
    </Border>
    <Border CornerRadius="18" BorderBrush="#1F2940" BorderThickness="1" ClipToBounds="True">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#141B2B" Offset="0"/>
          <GradientStop Color="#0E131F" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="48"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Title bar -->
        <Grid x:Name="TitleBar" Background="Transparent" Margin="18,0,8,0">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border Width="10" Height="10" CornerRadius="2" Background="#3B9BFF" Margin="0,0,3,0"/>
            <Border Width="10" Height="10" CornerRadius="2" Background="#FF8A2F" Margin="0,0,10,0"/>
            <TextBlock x:Name="TxtAppName" Foreground="#EAF0FA" FontWeight="Bold" FontSize="12"/>
            <TextBlock Text="&#x00B7;" Foreground="#5C6780" FontSize="12" Margin="8,0,8,0"/>
            <TextBlock Text="Rocket League" Foreground="#5C6780" FontSize="12"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Button x:Name="BtnLang" Style="{StaticResource Chrome}">
              <TextBlock x:Name="TxtLang" FontSize="12" FontWeight="SemiBold"/>
            </Button>
            <Button x:Name="BtnMin" Style="{StaticResource Chrome}">
              <TextBlock Text="&#xE921;" FontFamily="Segoe MDL2 Assets" FontSize="10"/>
            </Button>
            <Button x:Name="BtnClose" Style="{StaticResource Chrome}">
              <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="10"/>
            </Button>
          </StackPanel>
        </Grid>

        <StackPanel Grid.Row="1" Margin="26,4,26,22">
          <!-- Status orb -->
          <Grid Width="156" Height="156" Margin="0,10,0,0" HorizontalAlignment="Center">
            <Ellipse x:Name="Halo" Width="156" Height="156" Opacity="0.18"/>
            <Ellipse x:Name="Ring" Width="124" Height="124" StrokeThickness="2.5" Fill="#0B101A"/>
            <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="46"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>

          <TextBlock x:Name="StatusTitle" FontSize="30" FontWeight="Black" HorizontalAlignment="Center" Margin="0,16,0,0"/>
          <TextBlock x:Name="StatusSub" FontSize="13" Foreground="#8A96AD" TextAlignment="Center"
                     TextWrapping="Wrap" HorizontalAlignment="Center" Margin="10,4,10,0" MinHeight="36"/>

          <!-- Allow / Block switch -->
          <Border x:Name="Switch" Height="56" CornerRadius="14" Background="#0A0E17" BorderBrush="#1F2940"
                  BorderThickness="1" Padding="5" Margin="0,20,0,0">
            <Grid x:Name="SwitchGrid">
              <Grid.ColumnDefinitions>
                <ColumnDefinition/>
                <ColumnDefinition/>
              </Grid.ColumnDefinitions>
              <Border x:Name="Thumb" CornerRadius="10"/>
              <Button x:Name="BtnAllow" Grid.Column="0" Style="{StaticResource Seg}">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE785;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <TextBlock x:Name="TxtAllow"/>
                </StackPanel>
              </Button>
              <Button x:Name="BtnBlock" Grid.Column="1" Style="{StaticResource Seg}">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <TextBlock x:Name="TxtBlock"/>
                </StackPanel>
              </Button>
            </Grid>
          </Border>

          <!-- Firewall warning banner -->
          <Border x:Name="WarnBox" Visibility="Collapsed" CornerRadius="10" Background="#2A2115"
                  BorderBrush="#5A4423" BorderThickness="1" Padding="12,9" Margin="0,12,0,0">
            <TextBlock x:Name="WarnText" Foreground="#E0A95A" FontSize="12" TextWrapping="Wrap"/>
          </Border>

          <!-- Error banner -->
          <Border x:Name="ErrorBox" Visibility="Collapsed" CornerRadius="10" Background="#2A1520"
                  BorderBrush="#5A2334" BorderThickness="1" Padding="12,9" Margin="0,12,0,0">
            <TextBlock x:Name="ErrorText" Foreground="#FF9DB0" FontSize="12" TextWrapping="Wrap"/>
          </Border>

          <!-- Details card -->
          <Border CornerRadius="14" Background="#121827" BorderBrush="#1F2940" BorderThickness="1"
                  Padding="16,14" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock x:Name="TxtRangesHdr" Foreground="#5C6780" FontSize="10.5" FontWeight="Bold"/>
              <WrapPanel x:Name="Ranges" Margin="0,8,0,0"/>
              <Border Height="1" Background="#1F2940" Margin="0,12,0,12"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition/>
                  <ColumnDefinition/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal">
                  <Ellipse x:Name="DotOut" Width="8" Height="8" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <TextBlock x:Name="LblOut" Foreground="#8A96AD" FontSize="12.5" Margin="0,0,4,0"/>
                  <TextBlock x:Name="TxtOut" Foreground="#EAF0FA" FontSize="12.5" FontWeight="SemiBold"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                  <Ellipse x:Name="DotIn" Width="8" Height="8" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <TextBlock x:Name="LblIn" Foreground="#8A96AD" FontSize="12.5" Margin="0,0,4,0"/>
                  <TextBlock x:Name="TxtIn" Foreground="#EAF0FA" FontSize="12.5" FontWeight="SemiBold"/>
                </StackPanel>
              </Grid>
              <TextBlock x:Name="SyncNote" Visibility="Collapsed" Margin="0,12,0,0" FontSize="11.5" Foreground="#E0A95A"
                         TextWrapping="Wrap"/>
            </StackPanel>
          </Border>

          <TextBlock Foreground="#5C6780" FontSize="11.5" TextWrapping="Wrap" TextAlignment="Center" Margin="0,16,0,0">
            <Run Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="12"/><Run Text="  "/><Run x:Name="TxtHint"/>
          </TextBlock>
          <TextBlock x:Name="TxtUpdate" Visibility="Collapsed" Foreground="#3B9BFF" FontSize="11.5" FontWeight="SemiBold"
                     Cursor="Hand" TextAlignment="Center" Margin="0,8,0,0"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Root','TitleBar','BtnLang','TxtLang','BtnMin','BtnClose','TxtAppName','Halo','Ring','Glyph','StatusTitle',
               'StatusSub','Switch','Thumb','BtnAllow','BtnBlock','TxtAllow','TxtBlock','WarnBox','WarnText','ErrorBox',
               'ErrorText','TxtRangesHdr','Ranges','DotOut','DotIn','LblOut','LblIn','TxtOut','TxtIn','SyncNote',
               'TxtHint','TxtUpdate') {
    $ui[$n] = $window.FindName($n)
}

function New-Brush([string]$hex) {
    New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex))
}

$States = @{
    On      = @{ Color = '#FF8A2F'; Glyph = [string][char]0xE72E }
    Off     = @{ Color = '#3B9BFF'; Glyph = [string][char]0xE785 }
    Partial = @{ Color = '#FF5C7A'; Glyph = [string][char]0xE7BA }
    Missing = @{ Color = '#8A96AD'; Glyph = [string][char]0xE7BA }
}
$script:lastStatus = 'Off'
$script:busy = $false
$script:updateVersion = $null

# ---- Status icons -------------------------------------------------------
# The taskbar icon and the shortcut icons follow the status. Each state is drawn
# once into a multi-size .ico next to the script (bump -v1 to bust Explorer's icon cache).
$IconShapes = @{
    On      = 'M2.5,8 H13.5 V14 H2.5 Z M7,10 H9 V12 H7 Z M4,8 V6 A4,4 0 0 1 12,6 V8 H10 V6 A2,2 0 0 0 6,6 V8 Z'
    Off     = 'M2.5,8 H13.5 V14 H2.5 Z M7,10 H9 V12 H7 Z M4,8 V5 A4,4 0 0 1 12,5 V6.5 H10 V5 A2,2 0 0 0 6,5 V8 Z'
    Warning = 'M8,1.5 L15,14 H1 Z M7,5.5 H9 V10 H7 Z M7,11 H9 V13 H7 Z'
}
$IconSizes = 16, 20, 24, 32, 40, 48, 64, 256
$script:iconCache = @{}
$script:shortcutStatus = $null

function New-IconBitmap([string]$status, [int]$px) {
    $shape = if ($status -in 'On', 'Off') { $IconShapes[$status] } else { $IconShapes.Warning }
    $k = $px / 16.0
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform $k, $k))
    $dc.DrawRoundedRectangle((New-Brush $States[$status].Color), $null, (New-Object Windows.Rect 0, 0, 16, 16), 3.5, 3.5)
    $dc.DrawGeometry((New-Brush '#0A0E17'), $null, [Windows.Media.Geometry]::Parse('F0 ' + $shape))
    $dc.Pop(); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $px, $px, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $rtb
}

function Get-IconFile([string]$status) {
    $path = Join-Path $IconDir ('rl-me-{0}-v1.ico' -f $status.ToLower())
    if (Test-Path -LiteralPath $path) { return $path }
    [void](New-Item -ItemType Directory -Path $IconDir -Force -ErrorAction Stop)
    $pngs = @(foreach ($px in $IconSizes) {
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create((New-IconBitmap $status $px)))
        $ms = New-Object IO.MemoryStream
        $enc.Save($ms)
        , $ms.ToArray()
    })
    # ICONDIR, one ICONDIRENTRY per size (a width/height byte of 0 means 256), then the PNG frames
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $ms
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$IconSizes.Count)
    $offset = 6 + 16 * $IconSizes.Count
    for ($i = 0; $i -lt $IconSizes.Count; $i++) {
        $b = [byte]($IconSizes[$i] % 256)
        $bw.Write($b); $bw.Write($b); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($path, $ms.ToArray())
    $path
}

function Get-IconFrame([string]$status) {
    if (-not $script:iconCache[$status]) {
        $stream = [IO.File]::OpenRead((Get-IconFile $status))
        try {
            # Decoding the whole .ico lets WPF pick the 16px and 32px frames for the taskbar
            $dec = New-Object Windows.Media.Imaging.IconBitmapDecoder $stream, 'None', 'OnLoad'
            $script:iconCache[$status] = $dec.Frames[0]
        } finally { $stream.Dispose() }
    }
    $script:iconCache[$status]
}

function Update-ShortcutIcon([string]$status, [string[]]$SearchDirs = $ShortcutDirs) {
    if ($status -eq $script:shortcutStatus) { return }
    $icon = "$(Get-IconFile $status),0"
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($dir in $SearchDirs) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.lnk -ErrorAction SilentlyContinue) {
            try {
                $lnk = $wsh.CreateShortcut($f.FullName)
                if ($lnk.Arguments.IndexOf($AppScript, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                if ($lnk.IconLocation -ne $icon) {
                    $lnk.IconLocation = $icon
                    $lnk.Save()
                    [RLBlockME.Native]::SHChangeNotify(0x2000, 0x5, $f.FullName, [IntPtr]::Zero)   # SHCNE_UPDATEITEM, SHCNF_PATHW
                }
            } catch { }
        }
    }
    $script:shortcutStatus = $status
}

# One shared accent brush, animated between state colors
$accent = New-Brush '#3B9BFF'
$ui.Halo.Fill = $accent; $ui.Ring.Stroke = $accent; $ui.Glyph.Foreground = $accent
$ui.StatusTitle.Foreground = $accent; $ui.Thumb.Background = $accent
$ui.Halo.Effect = New-Object Windows.Media.Effects.BlurEffect
$ui.Halo.Effect.Radius = 20
$thumbX = New-Object Windows.Media.TranslateTransform
$ui.Thumb.RenderTransform = $thumbX

function Show-Ranges {
    $ui.Ranges.Children.Clear()
    foreach ($c in $Cidrs) {
        $chip = New-Object Windows.Controls.Border
        $chip.CornerRadius = New-Object Windows.CornerRadius 7
        $chip.Background = New-Brush '#1A2236'
        $chip.Padding = New-Object Windows.Thickness 9, 4, 9, 4
        $chip.Margin = New-Object Windows.Thickness 0, 0, 6, 6
        $chip.FlowDirection = 'LeftToRight'   # keep "/16" on the right in Arabic
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $c
        $tb.FontFamily = New-Object Windows.Media.FontFamily 'Consolas'
        $tb.FontSize = 12
        $tb.Foreground = New-Brush '#C5CFE0'
        $chip.Child = $tb
        [void]$ui.Ranges.Children.Add($chip)
    }
}

function New-Anim($type, $to) {
    $a = New-Object "Windows.Media.Animation.$type"
    $a.To = $to
    $a.Duration = [Windows.Duration][TimeSpan]::FromMilliseconds(280)
    $ease = New-Object Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'
    $a.EasingFunction = $ease
    $a
}

function Move-Thumb([string]$status) {
    $x = if ($status -eq 'On') { $ui.Thumb.ActualWidth } else { 0 }
    $thumbX.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (New-Anim DoubleAnimation ([double]$x)))
    $ui.Thumb.Opacity = if ($status -in 'On', 'Off') { 1 } else { 0 }
}

function Show-Error([string]$msg) {
    $ui.ErrorText.Text = $msg
    $ui.ErrorBox.Visibility = if ($msg) { 'Visible' } else { 'Collapsed' }
}

function Show-Update {
    if (-not $script:updateVersion) { return }
    $ui.TxtUpdate.Text = (L 'Update') -f $script:updateVersion
    $ui.TxtUpdate.Visibility = 'Visible'
}

function Apply-Language {
    $ui.Root.FlowDirection = if ($script:Lang -eq 'ar') { 'RightToLeft' } else { 'LeftToRight' }
    $window.Title          = L 'WindowTitle'
    $ui.TxtAppName.Text    = L 'AppName'
    $ui.TxtLang.Text       = L 'OtherLang'
    $ui.BtnLang.ToolTip    = L 'LangTip'
    $ui.TxtAllow.Text      = L 'Allow'
    $ui.TxtBlock.Text      = L 'Block'
    $ui.TxtRangesHdr.Text  = L 'RangesHeader'
    $ui.LblOut.Text        = L 'Outbound'
    $ui.LblIn.Text         = L 'Inbound'
    $ui.SyncNote.Text      = L 'SyncNote'
    $ui.TxtHint.Text       = L 'Hint'
    Show-Update
}

function Refresh-UI {
    try { $s = Get-BlockState } catch { Show-Error ((L 'ErrRead') -f $_.Exception.Message); return }
    $script:lastStatus = $s.Status
    $st = $States[$s.Status]

    $accent.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,
        (New-Anim ColorAnimation ([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($st.Color))))
    $ui.Glyph.Text       = $st.Glyph
    $ui.StatusTitle.Text = L "$($s.Status)Title"
    $ui.StatusSub.Text   = L "$($s.Status)Sub"
    Move-Thumb $s.Status

    $dark = New-Brush '#0A0E17'; $dim = New-Brush '#8A96AD'
    $ui.BtnBlock.Foreground = if ($s.Status -eq 'On')  { $dark } else { $dim }
    $ui.BtnAllow.Foreground = if ($s.Status -eq 'Off') { $dark } else { $dim }

    $onDot = New-Brush $States.On.Color; $offDot = New-Brush '#3A4560'
    $ui.DotOut.Fill = if ($s.Outbound) { $onDot } else { $offDot }
    $ui.DotIn.Fill  = if ($s.Inbound)  { $onDot } else { $offDot }
    $ui.TxtOut.Text = if ($s.Outbound) { L 'RuleOn' } else { L 'RuleOff' }
    $ui.TxtIn.Text  = if ($s.Inbound)  { L 'RuleOn' } else { L 'RuleOff' }
    $ui.SyncNote.Visibility = if ($s.Saved) { 'Collapsed' } else { 'Visible' }

    $warn = Get-FirewallWarning
    $ui.WarnText.Text = $warn
    $ui.WarnBox.Visibility = if ($warn) { 'Visible' } else { 'Collapsed' }

    # Taskbar + shortcut icons follow the status; icon trouble must never break the UI
    try { $window.Icon = Get-IconFrame $s.Status } catch { }
    try { Update-ShortcutIcon $s.Status } catch { }
}

function Invoke-Toggle([bool]$On) {
    if ($script:busy) { return }
    $script:busy = $true
    Show-Error ''
    $ui.Switch.Opacity = 0.6
    $ui.StatusSub.Text = if ($On) { L 'Blocking' } else { L 'Allowing' }
    $window.Cursor = [Windows.Input.Cursors]::Wait
    # Let the "working" state paint before the (blocking) firewall calls
    $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
    try     { Set-BlockState $On }
    catch   { Show-Error $_.Exception.Message }
    finally {
        $window.Cursor = $null
        $ui.Switch.Opacity = 1
        $script:busy = $false
        Refresh-UI
    }
}

# ---- Online ME6 list + update check ---------------------------------------
# ranges.json in the GitHub repo holds the current ME6 ranges and the latest version, so a
# range change reaches everyone without a new download. Fetched in the background; any
# failure (offline, GitHub down) just keeps the list we already have.
function Apply-Remote($data) {
    try {
        if ($data.latestVersion -and ([version]"$($data.latestVersion)" -gt [version]$AppVersion)) {
            $script:updateVersion = "$($data.latestVersion)"
            Show-Update
        }
    } catch { }
    if (-not (Test-Cidrs $data.ranges)) { return }
    if ((Get-RangesKey $data.ranges) -eq (Get-RangesKey $Cidrs)) { return }
    $script:Cidrs = @($data.ranges)
    try { $data | ConvertTo-Json | Set-Content -LiteralPath $RangesFile -Encoding UTF8 } catch { }
    Show-Ranges
    if ($script:busy) { return }   # the toggle in progress calls Ensure-Rules itself
    try { Ensure-Rules } catch { Show-Error ((L 'ErrPrepare') -f $_.Exception.Message) }
    Refresh-UI
}

function Start-RemoteCheck {
    try {
        Add-Type -AssemblyName System.Net.Http
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(15)
        $script:remoteTask = $client.GetStringAsync($RemoteUrl)
    } catch { return }
    # Poll the task from the UI thread instead of handling a callback on another thread
    $script:remoteTimer = New-Object Windows.Threading.DispatcherTimer
    $script:remoteTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:remoteTimer.Add_Tick({
        if (-not $script:remoteTask.IsCompleted) { return }
        $script:remoteTimer.Stop()
        if ($script:remoteTask.Status -ne 'RanToCompletion') { return }
        try { Apply-Remote ($script:remoteTask.Result | ConvertFrom-Json) } catch { }
    })
    $script:remoteTimer.Start()
}

$ui.BtnAllow.Add_Click({ Invoke-Toggle $false })
$ui.BtnBlock.Add_Click({ Invoke-Toggle $true })
$ui.BtnClose.Add_Click({ $window.Close() })
$ui.BtnMin.Add_Click({ $window.WindowState = 'Minimized' })
$ui.BtnLang.Add_Click({
    $script:Lang = if ($script:Lang -eq 'ar') { 'en' } else { 'ar' }
    try { @{ lang = $script:Lang } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 } catch { }
    Apply-Language
    if (-not $script:busy) { Refresh-UI }
})
# The browser is opened through Explorer so it doesn't run as Administrator
$ui.TxtUpdate.Add_MouseLeftButtonUp({ Start-Process explorer.exe "$RepoUrl/releases/latest" })
$ui.TitleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
$ui.Thumb.Add_SizeChanged({ Move-Thumb $script:lastStatus })
$window.Add_Activated({ if (-not $script:busy) { Refresh-UI } })   # picks up changes made outside the app

# After the UAC prompt the window can open minimized or behind other apps - bring it forward.
$window.Add_Loaded({
    $window.WindowState = 'Normal'
    $window.Topmost = $true
    $window.Activate()
    $window.Topmost = $false
    Start-RemoteCheck
})
Apply-Language
Show-Ranges
try   { Ensure-Rules }
catch { Show-Error ((L 'ErrPrepare') -f $_.Exception.Message) }
Refresh-UI
[void]$window.ShowDialog()
