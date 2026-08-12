unit wwCore;
{ wworld: базовые типы, детерминированный ГПСЧ и контейнеры.
  Только ООП: свободных процедур/функций в модуле нет, всё — методы классов. }

{$MODE OBJFPC}{$H+}

interface

const
  { коды клеток карты (значения попадают в CSV как есть) }
  WW_ROCK       = 0;   { монолит }
  WW_WALL       = 1;   { стена (порождается на финальном проходе) }
  WW_ROOM       = 2;   { пол комнаты }
  WW_COR_MINOR  = 3;   { побочный коридор, 1 клетка }
  WW_COR_SECOND = 4;   { второстепенный коридор, 2 клетки }
  WW_COR_MAIN   = 5;   { главный коридор, 3 клетки }
  WW_JUNCTION   = 6;   { запланированное пересечение коридоров }
  WW_FORK       = 7;   { узел-развилка }
  WW_STAIR_UP   = 8;
  WW_STAIR_DOWN = 9;

  WW_NO_OWNER   = -1;

type
  TWwRoomKind = (wrkSmall, wrkMedium, wrkLarge);
  TWwLinkKind = (wlkPortal, wlkJunction, wlkFork);

  { TWwIntList — минимальный список целых }
  TWwIntList = class
  private
    FItems: array of Integer;
    FCount: Integer;
    function GetItem(AIndex: Integer): Integer;
  public
    constructor Create;
    procedure Add(AValue: Integer);
    procedure AddUnique(AValue: Integer);
    procedure Clear;
    function Contains(AValue: Integer): Boolean;
    property Count: Integer read FCount;
    property Items[AIndex: Integer]: Integer read GetItem; default;
  end;

  { TWwPointList — список координат }
  TWwPointList = class
  private
    FXs, FYs: array of Integer;
    FCount: Integer;
    function GetX(AIndex: Integer): Integer;
    function GetY(AIndex: Integer): Integer;
  public
    constructor Create;
    procedure Add(AX, AY: Integer);
    procedure Clear;
    function Contains(AX, AY: Integer): Boolean;
    property Count: Integer read FCount;
    property X[AIndex: Integer]: Integer read GetX;
    property Y[AIndex: Integer]: Integer read GetY;
  end;

  { TWwRandom — xorshift128+, полностью детерминирован и не зависит от RTL }
  TWwRandom = class
  private
    FS0, FS1: QWord;
    function Mix(AValue: QWord): QWord;
  public
    constructor Create(ASeed: QWord);
    function NextU64: QWord;
    function NextInt(ALo, AHi: Integer): Integer;
    function NextFloat: Double;
    function Chance(APercent: Integer): Boolean;
    function Derive(ATag: QWord): TWwRandom;
  end;

implementation

{ TWwIntList }

constructor TWwIntList.Create;
begin
  inherited Create;
  FCount := 0;
  SetLength(FItems, 8);
end;

function TWwIntList.GetItem(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    Result := -1
  else
    Result := FItems[AIndex];
end;

procedure TWwIntList.Add(AValue: Integer);
begin
  if FCount = Length(FItems) then
    SetLength(FItems, Length(FItems) * 2);
  FItems[FCount] := AValue;
  Inc(FCount);
end;

procedure TWwIntList.AddUnique(AValue: Integer);
begin
  if not Contains(AValue) then
    Add(AValue);
end;

procedure TWwIntList.Clear;
begin
  FCount := 0;
end;

function TWwIntList.Contains(AValue: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    if FItems[i] = AValue then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ TWwPointList }

constructor TWwPointList.Create;
begin
  inherited Create;
  FCount := 0;
  SetLength(FXs, 16);
  SetLength(FYs, 16);
end;

function TWwPointList.GetX(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Result := -1 else Result := FXs[AIndex];
end;

function TWwPointList.GetY(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Result := -1 else Result := FYs[AIndex];
end;

procedure TWwPointList.Add(AX, AY: Integer);
begin
  if FCount = Length(FXs) then
  begin
    SetLength(FXs, Length(FXs) * 2);
    SetLength(FYs, Length(FYs) * 2);
  end;
  FXs[FCount] := AX;
  FYs[FCount] := AY;
  Inc(FCount);
end;

procedure TWwPointList.Clear;
begin
  FCount := 0;
end;

function TWwPointList.Contains(AX, AY: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    if (FXs[i] = AX) and (FYs[i] = AY) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ TWwRandom }

function TWwRandom.Mix(AValue: QWord): QWord;
var
  z: QWord;
begin
  z := AValue + QWord($9E3779B97F4A7C15);
  z := (z xor (z shr 30)) * QWord($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * QWord($94D049BB133111EB);
  Result := z xor (z shr 31);
end;

constructor TWwRandom.Create(ASeed: QWord);
begin
  inherited Create;
  FS0 := Mix(ASeed);
  FS1 := Mix(FS0);
  if (FS0 = 0) and (FS1 = 0) then
  begin
    FS0 := 1;
    FS1 := 2;
  end;
end;

function TWwRandom.NextU64: QWord;
var
  s1, s0: QWord;
begin
  s1 := FS0;
  s0 := FS1;
  FS0 := s0;
  s1 := s1 xor (s1 shl 23);
  s1 := s1 xor (s1 shr 17);
  s1 := s1 xor s0;
  s1 := s1 xor (s0 shr 26);
  FS1 := s1;
  Result := FS1 + s0;
end;

function TWwRandom.NextInt(ALo, AHi: Integer): Integer;
begin
  if AHi <= ALo then
    Result := ALo
  else
    Result := ALo + Integer(NextU64 mod QWord(AHi - ALo + 1));
end;

function TWwRandom.NextFloat: Double;
begin
  Result := (NextU64 shr 11) / 9007199254740992.0;
end;

function TWwRandom.Chance(APercent: Integer): Boolean;
begin
  Result := NextInt(1, 100) <= APercent;
end;

function TWwRandom.Derive(ATag: QWord): TWwRandom;
begin
  Result := TWwRandom.Create(Mix(FS0 xor Mix(ATag)));
end;

end.
