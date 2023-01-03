{
  Copyright 2022-2023 Michalis Kamburelis

  Extensions to the Pascal Language Server specific to Castle Game Engine.

  Distributed on permissive "modified BSD 3-clause",
  https://github.com/castle-engine/castle-engine/blob/master/doc/licenses/COPYING.BSD-3-clause.txt ,
  so that it can be combined with any other licenses without issues. }

{ Autodetect OS and CPU.
  Adjusted from CGE ToolArchitectures unit,
  which in turn is based on FPC FPMkUnit. }
unit CastleArchitectures;

interface

function AutoDetectOS: String;
function AutoDetectCPU: String;

implementation

uses TypInfo;

type
  { Processor architectures supported by FPC. Copied from FPMkUnit. }
  TCpu=(cpuNone,
    i386,m68k,powerpc,sparc,x86_64,arm,powerpc64,avr,armeb,
    mips,mipsel,jvm,i8086,aarch64,sparc64
  );

  { Operating systems supported by FPC. Copied from FPMkUnit. }
  TOS=(osNone,
    linux,go32v2,win32,os2,freebsd,beos,netbsd,
    amiga,atari, solaris, qnx, netware, openbsd,wdosx,
    palmos,macosclassic,darwin,emx,watcom,morphos,netwlibc,
    win64,wince,gba,nds,embedded,symbian,haiku,iphonesim,
    aix,java,android,nativent,msdos,wii,aros,dragonfly,
    win16,ios
  );

const
  DefaultCPU: TCPU =
    {$ifdef CPUi386} i386 {$endif}
    {$ifdef CPUm68k} m68k {$endif}
    {$ifdef CPUpowerpc32} powerpc {$endif}
    {$ifdef CPUsparc} sparc {$endif}
    {$ifdef CPUx86_64} x86_64 {$endif}
    {$ifdef CPUarm} arm {$endif}
    {$ifdef CPUaarch64} aarch64 {$endif}
    {$ifdef CPUpowerpc64} powerpc64 {$endif}
    {$ifdef CPUavr} avr {$endif}
    {$ifdef CPUarmeb} armeb {$endif}
    {$ifdef CPUmips} mips {$endif}
    {$ifdef CPUmipsel} mipsel {$endif}
    {$ifdef CPUjvm} jvm {$endif}
    {$ifdef CPUi8086} i8086 {$endif}
    {$ifdef CPUsparc64} sparc64 {$endif}
  ;

  DefaultOS: TOS =
    {$ifdef linux} linux {$endif}
    {$ifdef go32v2} go32v2 {$endif}
    {$ifdef win32} win32 {$endif}
    {$ifdef os2} os2 {$endif}
    {$ifdef freebsd} freebsd {$endif}
    {$ifdef beos} beos {$endif}
    {$ifdef netbsd} netbsd {$endif}
    {$ifdef amiga} amiga {$endif}
    {$ifdef atari} atari {$endif}
    {$ifdef solaris} solaris {$endif}
    {$ifdef qnx} qnx {$endif}
    {$ifdef netware} netware {$endif}
    {$ifdef openbsd} openbsd {$endif}
    {$ifdef wdosx} wdosx {$endif}
    {$ifdef palmos} palmos {$endif}
    {$ifdef macosclassic} macosclassic {$endif} // TODO: what is symbol of this? It used to be macos?
    {$ifdef darwin} darwin {$endif}
    {$ifdef emx} emx {$endif}
    {$ifdef watcom} watcom {$endif}
    {$ifdef morphos} morphos {$endif}
    {$ifdef netwlibc} netwlibc {$endif}
    {$ifdef win64} win64 {$endif}
    {$ifdef wince} wince {$endif}
    {$ifdef gba} gba {$endif}
    {$ifdef nds} nds {$endif}
    {$ifdef embedded} embedded {$endif}
    {$ifdef symbian} symbian {$endif}
    {$ifdef haiku} haiku {$endif}
    {$ifdef iphonesim} iphonesim {$endif}
    {$ifdef aix} aix {$endif}
    {$ifdef java} java {$endif}
    {$ifdef android} android {$endif}
    {$ifdef nativent} nativent {$endif}
    {$ifdef msdos} msdos {$endif}
    {$ifdef wii} wii {$endif}
  ;

function CPUToString(CPU: TCPU): String;
begin
  Result := LowerCase(GetEnumName(TypeInfo(TCPU), Ord(CPU)));
end;

function OSToString(OS: TOS): String;
begin
  Result := LowerCase(GetEnumName(TypeInfo(TOS), Ord(OS)));
end;

function AutoDetectOS: String;
begin
  Result := OSToString(DefaultOS);
end;

function AutoDetectCPU: String;
begin
  Result := CPUToString(DefaultCPU);
end;

end.
