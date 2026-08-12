unit wwRules;
{ Правила прогрессии по этажам.

  Ранги коридоров:  1 — побочный (1 клетка), 2 — второстепенный (2),
                    3 — главный (3).
  Прогрессия:
    ур. 1-2  — только малые комнаты и побочные коридоры;
    ур. 3    — появляются средние комнаты и первый второстепенный коридор;
    ур. 5    — появляется первая большая комната (пока ведёт второстепенный,
               главные коридоры ещё не разблокированы — ширина коридора
               ограничена рангом уровня);
    ур. 6    — первый главный коридор;
    ур. 8    — разрешены составные (сложные) формы комнат.
  С шестого этажа максимальный (не минимальный) размер одного из типов
  комнат растёт на 1 в порядке: большая-средняя-большая-средняя-большая-малая. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, wwCore;

type
  TWwLevelRules = class
  private
    FLevel: Integer;
    FSmallCount, FMediumCount, FLargeCount: Integer;
    FMaxSmall, FMaxMedium, FMaxLarge: Integer;
    FMinSmall, FMinMedium, FMinLarge: Integer;
    FMaxRank: Integer;
    FAllowComposite: Boolean;
    FBudget: Integer;
    procedure ComputeCounts;
    procedure ComputeSizes;
    procedure ApplyBudget;
  public
    constructor Create(ALevel: Integer);
    function MaxSideFor(AKind: TWwRoomKind): Integer;
    function MinSideFor(AKind: TWwRoomKind): Integer;
    function CountFor(AKind: TWwRoomKind): Integer;
    function CostFor(AKind: TWwRoomKind): Integer;
    function RankFor(AKind: TWwRoomKind): Integer;
    function CorridorRank(AKindA, AKindB: TWwRoomKind): Integer;
    function MaxCorridorLength(ASizeA, ASizeB: Integer): Integer;
    function SpentBudget: Integer;
    property Level: Integer read FLevel;
    property MaxRank: Integer read FMaxRank;
    property AllowComposite: Boolean read FAllowComposite;
    property Budget: Integer read FBudget;
    property SmallCount: Integer read FSmallCount;
    property MediumCount: Integer read FMediumCount;
    property LargeCount: Integer read FLargeCount;
  end;

implementation

constructor TWwLevelRules.Create(ALevel: Integer);
begin
  inherited Create;
  FLevel := ALevel;
  if FLevel < 1 then FLevel := 1;
  if FLevel <= 2 then FMaxRank := 1
  else if FLevel <= 5 then FMaxRank := 2
  else FMaxRank := 3;
  FAllowComposite := FLevel >= 8;
  FBudget := 10 + 3 * FLevel;
  ComputeCounts;
  ComputeSizes;
  ApplyBudget;
end;

procedure TWwLevelRules.ComputeCounts;
begin
  FSmallCount := 3 + (FLevel + 1) div 2;
  if FSmallCount > 10 then FSmallCount := 10;

  if FLevel < 3 then
    FMediumCount := 0
  else
  begin
    FMediumCount := 1 + (FLevel - 1) div 2;
    if FMediumCount > 5 then FMediumCount := 5;
  end;

  if FLevel < 5 then
    FLargeCount := 0
  else
  begin
    FLargeCount := 1 + (FLevel - 5) div 3;
    if FLargeCount > 3 then FLargeCount := 3;
  end;
end;

procedure TWwLevelRules.ComputeSizes;
var
  l, slot: Integer;
begin
  FMinSmall := 3;  FMaxSmall := 5;
  FMinMedium := 6; FMaxMedium := 8;
  FMinLarge := 8;  FMaxLarge := 10;
  for l := 6 to FLevel do
  begin
    slot := (l - 6) mod 6;
    case slot of
      0, 2, 4: Inc(FMaxLarge);
      1, 3: Inc(FMaxMedium);
    else
      Inc(FMaxSmall);
    end;
  end;
end;

{ Общий лимит: комнаты большего размера стоят дороже. Если формульные
  количества не влезают в бюджет уровня — срезаем, начиная с малых. }
procedure TWwLevelRules.ApplyBudget;
begin
  while (SpentBudget > FBudget) and (FSmallCount > 2) do Dec(FSmallCount);
  while (SpentBudget > FBudget) and (FMediumCount > 0) do Dec(FMediumCount);
  while (SpentBudget > FBudget) and (FLargeCount > 0) do Dec(FLargeCount);
end;

function TWwLevelRules.SpentBudget: Integer;
begin
  Result := FSmallCount * CostFor(wrkSmall) +
            FMediumCount * CostFor(wrkMedium) +
            FLargeCount * CostFor(wrkLarge);
end;

function TWwLevelRules.CostFor(AKind: TWwRoomKind): Integer;
begin
  case AKind of
    wrkSmall: Result := 1;
    wrkMedium: Result := 3;
  else
    Result := 6;
  end;
end;

function TWwLevelRules.MaxSideFor(AKind: TWwRoomKind): Integer;
begin
  case AKind of
    wrkSmall: Result := FMaxSmall;
    wrkMedium: Result := FMaxMedium;
  else
    Result := FMaxLarge;
  end;
end;

function TWwLevelRules.MinSideFor(AKind: TWwRoomKind): Integer;
begin
  case AKind of
    wrkSmall: Result := FMinSmall;
    wrkMedium: Result := FMinMedium;
  else
    Result := FMinLarge;
  end;
end;

function TWwLevelRules.CountFor(AKind: TWwRoomKind): Integer;
begin
  case AKind of
    wrkSmall: Result := FSmallCount;
    wrkMedium: Result := FMediumCount;
  else
    Result := FLargeCount;
  end;
end;

function TWwLevelRules.RankFor(AKind: TWwRoomKind): Integer;
begin
  case AKind of
    wrkSmall: Result := 1;
    wrkMedium: Result := 2;
  else
    Result := 3;
  end;
end;

{ Ширина коридора соответствует наибольшей из связываемых комнат,
  но не выше ранга, разблокированного на этом этаже. }
function TWwLevelRules.CorridorRank(AKindA, AKindB: TWwRoomKind): Integer;
var
  r: Integer;
begin
  r := RankFor(AKindA);
  if RankFor(AKindB) > r then r := RankFor(AKindB);
  if r > FMaxRank then r := FMaxRank;
  Result := r;
end;

{ Максимальная длина коридора — не меньше удвоенной максимальной стороны
  большей из связываемых комнат. }
function TWwLevelRules.MaxCorridorLength(ASizeA, ASizeB: Integer): Integer;
var
  s: Integer;
begin
  s := ASizeA;
  if ASizeB > s then s := ASizeB;
  Result := 2 * s;
  if Result < 10 then Result := 10;
end;

end.
