<#
Windows player. Plays one PCM .wav at the plugin's volume; with -Loop it
repeats the file until the marker named by -StopFile appears, then fades out.

    play.ps1 -Path C:/plugin/sounds/done.wav -Volume 0.4
    play.ps1 -Path C:/plugin/sounds/ambient/dusk.wav -Volume 0.4 -Loop -StopFile C:/data/loop.stop.123

Everything here is winmm's waveOut API, called directly: the whole file goes
into one buffer that the device loops itself (WHDR_BEGINLOOP/ENDLOOP, no gap,
no restart). PlaySound/SoundPlayer would be simpler, but nothing can adjust
the volume of the stream it opens. WPF's MediaPlayer and the Windows Media
Player COM object need the Media Feature Pack, which N editions and some
managed machines lack; winmm is core Windows.

Volume is applied to the samples before they reach the device, so 0.4 means
the same as `afplay -v 0.4` on macOS. waveOutSetVolume on the stream handle
does work, but its scale is not linear — 0.4 came out inaudible — so it is
used only for the fade, where the shape matters less than the direction.

The P/Invoke stubs and the sample-scaling loop are emitted with
Reflection.Emit, so no C# compiler runs — Add-Type would add about a second
to every cue.

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
$device = [IntPtr]::Zero; $header = [IntPtr]::Zero; $buffer = [IntPtr]::Zero; $format = [IntPtr]::Zero
$M = [Runtime.InteropServices.Marshal]

try {
  # --- winmm, without a compiler -----------------------------------------
  $assembly = [AppDomain]::CurrentDomain.DefineDynamicAssembly(
    (New-Object Reflection.AssemblyName 'StayAwhileWinmm'), [Reflection.Emit.AssemblyBuilderAccess]::Run)
  $module = $assembly.DefineDynamicModule('StayAwhileWinmm', $false)
  $type = $module.DefineType('StayAwhile.Winmm', 'Public,Class,Sealed,Abstract')
  $imports = @{
    waveOutOpen            = [Type[]]@([IntPtr].MakeByRefType(), [uint32], [IntPtr], [IntPtr], [IntPtr], [uint32])
    waveOutPrepareHeader   = [Type[]]@([IntPtr], [IntPtr], [uint32])
    waveOutWrite           = [Type[]]@([IntPtr], [IntPtr], [uint32])
    waveOutSetVolume       = [Type[]]@([IntPtr], [uint32])
    waveOutReset           = [Type[]]@([IntPtr])
    waveOutUnprepareHeader = [Type[]]@([IntPtr], [IntPtr], [uint32])
    waveOutClose           = [Type[]]@([IntPtr])
  }
  foreach ($name in $imports.Keys) {
    $method = $type.DefinePInvokeMethod($name, 'winmm.dll', 'Public,Static,PinvokeImpl',
      [Reflection.CallingConventions]::Standard, [uint32], $imports[$name],
      [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
    $method.SetImplementationFlags($method.GetMethodImplementationFlags() -bor [Reflection.MethodImplAttributes]::PreserveSig)
  }
  $winmm = $type.CreateType()

  # --- the file: RIFF/WAVE with a PCM fmt chunk and a data chunk ---------
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 44 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
      [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'WAVE') { throw "not a WAV file: $Path" }
  $pos = 12; $fmtAt = -1; $dataAt = -1; $dataLen = 0
  while ($pos + 8 -le $bytes.Length) {
    $id = [Text.Encoding]::ASCII.GetString($bytes, $pos, 4)
    $size = [BitConverter]::ToInt32($bytes, $pos + 4)
    if ($id -eq 'fmt ') { $fmtAt = $pos + 8 }
    elseif ($id -eq 'data') { $dataAt = $pos + 8; $dataLen = [Math]::Min($size, $bytes.Length - $dataAt); break }
    $pos += 8 + $size + ($size % 2)          # chunks are word-aligned
  }
  if ($fmtAt -lt 0 -or $dataAt -lt 0 -or $dataLen -le 0) { throw "no fmt/data chunk: $Path" }
  $formatTag = [BitConverter]::ToUInt16($bytes, $fmtAt)
  if ($formatTag -ne 1) { throw "not PCM (format $formatTag): $Path" }

  # WAVEFORMATEX, 18 bytes: the fmt chunk's first 16 plus cbSize = 0.
  $format = $M::AllocHGlobal(18)
  $M::Copy($bytes, $fmtAt, $format, 16)
  $M::WriteInt16($format, 16, [int16]0)

  # --- open the default device ------------------------------------------
  $WAVE_MAPPER = [uint32]::MaxValue        # 0xFFFFFFFF, which PowerShell would read as -1
  $rc = $winmm::waveOutOpen([ref]$device, $WAVE_MAPPER, $format, [IntPtr]::Zero, [IntPtr]::Zero, [uint32]0)
  if ($rc -ne 0) { throw "waveOutOpen failed ($rc)" }
  function Set-StreamVolume([double]$level) {   # fade only; see the header comment
    $unit = [uint32][Math]::Round([Math]::Max(0, [Math]::Min(1, $level)) * 0xFFFF)   # both channels
    [void]$winmm::waveOutSetVolume($device, (($unit -shl 16) -bor $unit))
  }
  Set-StreamVolume 1

  # --- one buffer holding the whole file, looped by the device -----------
  $buffer = $M::AllocHGlobal($dataLen)
  $bits = [BitConverter]::ToUInt16($bytes, $fmtAt + 14)
  $level = [Math]::Max(0, [Math]::Min(1, $Volume))
  if ($bits -eq 16 -and $level -lt 1) {
    # a[i] = (short)((a[i] * gain) >> 16), gain = level * 65536, as IL: a
    # PowerShell loop over a minute of audio would take longer than the fade.
    $scaler = New-Object Reflection.Emit.DynamicMethod('Scale', [void], [Type[]]@([int16[]], [int]), [object].Module)
    $il = $scaler.GetILGenerator(); [void]$il.DeclareLocal([int])
    $body = $il.DefineLabel(); $check = $il.DefineLabel(); $op = [Reflection.Emit.OpCodes]
    $il.Emit($op::Ldc_I4_0); $il.Emit($op::Stloc_0); $il.Emit($op::Br, $check)
    $il.MarkLabel($body)
    $il.Emit($op::Ldarg_0); $il.Emit($op::Ldloc_0)
    $il.Emit($op::Ldarg_0); $il.Emit($op::Ldloc_0); $il.Emit($op::Ldelem_I2)
    $il.Emit($op::Ldarg_1); $il.Emit($op::Mul); $il.Emit($op::Ldc_I4, 16); $il.Emit($op::Shr)
    $il.Emit($op::Conv_I2); $il.Emit($op::Stelem_I2)
    $il.Emit($op::Ldloc_0); $il.Emit($op::Ldc_I4_1); $il.Emit($op::Add); $il.Emit($op::Stloc_0)
    $il.MarkLabel($check)
    $il.Emit($op::Ldloc_0); $il.Emit($op::Ldarg_0); $il.Emit($op::Ldlen); $il.Emit($op::Conv_I4); $il.Emit($op::Blt, $body)
    $il.Emit($op::Ret)
    # A typed delegate: MethodInfo.Invoke would hand the array over wrapped in a PSObject.
    $scale = $scaler.CreateDelegate([System.Action`2].MakeGenericType([int16[]], [int]))
    $samples = New-Object int16[] ([int]($dataLen / 2))
    [Buffer]::BlockCopy($bytes, $dataAt, $samples, 0, $samples.Length * 2)
    $scale.Invoke($samples, [int]($level * 65536))
    $M::Copy($samples, 0, $buffer, $samples.Length)
  } else {
    $M::Copy($bytes, $dataAt, $buffer, $dataLen)
  }
  # WAVEHDR: lpData, dwBufferLength, dwBytesRecorded, dwUser, dwFlags, dwLoops, lpNext, reserved
  $p = [IntPtr]::Size                        # 8 on x64, 4 on x86; fields align to it
  $oLen = $p; $oFlags = 2 * $p + 8; $oLoops = $oFlags + 4; $headerSize = 2 * $p + 16 + 2 * $p
  $header = $M::AllocHGlobal($headerSize)
  for ($i = 0; $i -lt $headerSize; $i++) { $M::WriteByte($header, $i, 0) }
  $M::WriteIntPtr($header, 0, $buffer)
  $M::WriteInt32($header, $oLen, $dataLen)
  $rc = $winmm::waveOutPrepareHeader($device, $header, [uint32]$headerSize)
  if ($rc -ne 0) { throw "waveOutPrepareHeader failed ($rc)" }
  if ($Loop) {
    $flags = $M::ReadInt32($header, $oFlags) -bor 0x4 -bor 0x8      # WHDR_BEGINLOOP | WHDR_ENDLOOP
    $M::WriteInt32($header, $oFlags, $flags)
    $M::WriteInt32($header, $oLoops, -1)                            # 0xFFFFFFFF: until told to stop
  }
  $rc = $winmm::waveOutWrite($device, $header, [uint32]$headerSize)
  if ($rc -ne 0) { throw "waveOutWrite failed ($rc)" }

  if (-not $Loop) {
    # A cue: wait for WHDR_DONE, with a ceiling in case the device never says so.
    $channels = [BitConverter]::ToUInt16($bytes, $fmtAt + 2)
    $rate = [BitConverter]::ToInt32($bytes, $fmtAt + 4)
    $seconds = $dataLen / [Math]::Max(1, $rate * $channels * [Math]::Max(1, $bits / 8))
    $deadline = (Get-Date).AddSeconds($seconds + 2)
    while ((($M::ReadInt32($header, $oFlags)) -band 0x1) -eq 0 -and (Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 50
    }
    exit 0
  }

  while ($true) {
    Start-Sleep -Milliseconds 100
    if ($StopFile -and (Test-Path -LiteralPath $StopFile)) {
      $steps = 15
      for ($i = 1; $i -le $steps; $i++) {
        Set-StreamVolume (1 - $i / $steps)
        Start-Sleep -Milliseconds ([int](1000 * $Fade / $steps))
      }
      exit 0
    }
  }
} catch {
  [Console]::Error.WriteLine("play.ps1: $($_.Exception.Message)")
  exit 1
} finally {
  if ($device -ne [IntPtr]::Zero) {
    [void]$winmm::waveOutReset($device)
    if ($header -ne [IntPtr]::Zero) { [void]$winmm::waveOutUnprepareHeader($device, $header, [uint32]$headerSize) }
    [void]$winmm::waveOutClose($device)
  }
  foreach ($block in $header, $buffer, $format) { if ($block -ne [IntPtr]::Zero) { $M::FreeHGlobal($block) } }
}
