<#
Windows player. Plays one .wav at the plugin's volume; with -Loop it repeats
the file until the marker named by -StopFile appears, then fades out.

    play.ps1 -Path C:/plugin/sounds/done.wav -Volume 0.4
    play.ps1 -Path C:/plugin/sounds/ambient/dusk.wav -Volume 0.4 -Loop -StopFile C:/data/loop.stop.123

Everything here is winmm, reached through System.Media.SoundPlayer: PlaySound's
own SND_LOOP repeats a file with no gap and no process restart, and
waveOutSetVolume scales only this process's audio session (Vista and later).
WPF's MediaPlayer and the Windows Media Player COM object would be nicer, but
both need the Media Feature Pack, which N editions and some managed machines
lack; winmm is core Windows. The P/Invoke stub is emitted with Reflection.Emit
so no C# compiler runs — Add-Type would add about a second to every cue.

Paths may use forward slashes. lib.sh passes them that way so the command line
still contains the plugin root that ours() looks for.
#>
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [double]$Volume = 0.4,
  [switch]$Loop,
  [string]$StopFile = "",
  [double]$Fade = 0.9
)

$ErrorActionPreference = 'Stop'
try {
  $assembly = [AppDomain]::CurrentDomain.DefineDynamicAssembly(
    (New-Object Reflection.AssemblyName 'StayAwhileWinmm'), [Reflection.Emit.AssemblyBuilderAccess]::Run)
  $module = $assembly.DefineDynamicModule('StayAwhileWinmm', $false)
  $type = $module.DefineType('StayAwhile.Winmm', 'Public,Class,Sealed,Abstract')
  $method = $type.DefinePInvokeMethod('waveOutSetVolume', 'winmm.dll', 'Public,Static,PinvokeImpl',
    [Reflection.CallingConventions]::Standard, [uint32], [Type[]]@([IntPtr], [uint32]),
    [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
  $method.SetImplementationFlags($method.GetMethodImplementationFlags() -bor [Reflection.MethodImplAttributes]::PreserveSig)
  $winmm = $type.CreateType()

  function Set-SessionVolume([double]$level) {
    # Both channels, 0..0xFFFF each. Device 0 stands for this process's session.
    $unit = [uint32][Math]::Round([Math]::Max(0, [Math]::Min(1, $level)) * 0xFFFF)
    [void]$winmm::waveOutSetVolume([IntPtr]::Zero, (($unit -shl 16) -bor $unit))
  }

  $player = New-Object System.Media.SoundPlayer $Path
  $player.Load()                     # throws when the file is missing or not PCM
  Set-SessionVolume $Volume

  if (-not $Loop) {
    $player.PlaySync()
    exit 0
  }

  $player.PlayLooping()
  Set-SessionVolume $Volume          # the session exists now; make sure it took
  while ($true) {
    Start-Sleep -Milliseconds 100
    if ($StopFile -and (Test-Path -LiteralPath $StopFile)) {
      $steps = 15
      for ($i = 1; $i -le $steps; $i++) {
        Set-SessionVolume ($Volume * (1 - $i / $steps))
        Start-Sleep -Milliseconds ([int](1000 * $Fade / $steps))
      }
      $player.Stop()
      exit 0
    }
  }
} catch {
  [Console]::Error.WriteLine("play.ps1: $($_.Exception.Message)")
  exit 1
}
