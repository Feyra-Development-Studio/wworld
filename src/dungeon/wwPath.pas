unit wwPath;
{ Поиск пути по сетке для ходьбы указанием клетки.

  Вынесено отдельным модулем нарочно: указывать клетку можно мышью на
  настольных платформах и касанием на Android, но сам поиск от способа
  указания не зависит вовсе. Отдельный модуль ещё и проверяется в CI без
  окна — а окна там нет ни у BearLibTerminal, ни у эмулятора на первых порах.

  Правило перехода здесь ровно то же, что у TWwViewer.TryMove: клетка должна
  быть проходимой. Диагонали разрешены, включая проход между двумя стенами по
  диагонали — так ходит и клавиатура (QEZC), и расходиться эти два способа
  движения не должны, иначе указанием окажется достижимо не то же самое, что
  клавишами.

  Обход в ширину, а не A*: поле у нас меньше сотни клеток в стороне, разница
  незаметна, а поведение обхода в ширину предсказуемо — путь всегда с
  наименьшим числом шагов, и при равенстве всегда один и тот же. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, wwGrid;

type
  { Шаг пути: смещение на одну клетку, как его понимает TryMove. }
  TWwStep = record
    DX, DY: Integer;
  end;

  TWwPath = array of TWwStep;

{ Ищет кратчайший путь от (AFromX, AFromY) до (AToX, AToY).

  Возвращает True и заполняет APath, если путь есть. Пустой путь (нулевой
  длины) — это тоже успех: указали на клетку, где уже стоим.

  При неудаче APath пуст, а AReason содержит причину, пригодную для показа
  человеку: молчаливый отказ неотличим от промаха мимо клетки. }
function WwFindPath(AGrid: TWwGrid; AFromX, AFromY, AToX, AToY: Integer;
  out APath: TWwPath; out AReason: string): Boolean;

implementation

const
  { Порядок соседей: сначала прямые, потом диагонали. Он определяет, какой
    из равных по длине путей выберется, поэтому зафиксирован — от него
    зависит воспроизводимость проверок. }
  NEIGHBOURS: array[0..7, 0..1] of Integer =
    ((0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1));

function WwFindPath(AGrid: TWwGrid; AFromX, AFromY, AToX, AToY: Integer;
  out APath: TWwPath; out AReason: string): Boolean;
var
  came: array of Integer;      { откуда пришли, индекс клетки или -1 }
  queue: array of Integer;
  head, tail, cur, nx, ny, cx, cy, n, idx, steps, i: Integer;
begin
  Result := False;
  APath := nil;
  AReason := '';

  if AGrid = nil then
  begin
    AReason := 'карта не загружена';
    Exit;
  end;

  if not AGrid.InBounds(AToX, AToY) then
  begin
    AReason := 'это за краем карты';
    Exit;
  end;

  if (AFromX = AToX) and (AFromY = AToY) then
  begin
    SetLength(APath, 0);
    Result := True;
    Exit;
  end;

  if not AGrid.IsWalkable(AToX, AToY) then
  begin
    AReason := 'туда не пройти: там стена';
    Exit;
  end;

  SetLength(came, AGrid.W * AGrid.H);
  for i := 0 to Length(came) - 1 do
    came[i] := -2;                      { -2 — не посещали }

  SetLength(queue, AGrid.W * AGrid.H);
  head := 0;
  tail := 0;
  idx := AFromY * AGrid.W + AFromX;
  came[idx] := -1;                      { -1 — начало }
  queue[tail] := idx;
  Inc(tail);

  while head < tail do
  begin
    cur := queue[head];
    Inc(head);
    cx := cur mod AGrid.W;
    cy := cur div AGrid.W;

    if (cx = AToX) and (cy = AToY) then
    begin
      { Разворачиваем путь от цели к началу, потом переворачиваем. }
      steps := 0;
      idx := cur;
      while came[idx] <> -1 do
      begin
        Inc(steps);
        idx := came[idx];
      end;

      SetLength(APath, steps);
      idx := cur;
      i := steps - 1;
      while came[idx] <> -1 do
      begin
        APath[i].DX := (idx mod AGrid.W) - (came[idx] mod AGrid.W);
        APath[i].DY := (idx div AGrid.W) - (came[idx] div AGrid.W);
        idx := came[idx];
        Dec(i);
      end;

      Result := True;
      Exit;
    end;

    for n := 0 to High(NEIGHBOURS) do
    begin
      nx := cx + NEIGHBOURS[n, 0];
      ny := cy + NEIGHBOURS[n, 1];
      if not AGrid.InBounds(nx, ny) then Continue;
      if not AGrid.IsWalkable(nx, ny) then Continue;
      idx := ny * AGrid.W + nx;
      if came[idx] <> -2 then Continue;
      came[idx] := cur;
      queue[tail] := idx;
      Inc(tail);
    end;
  end;

  { Клетка проходимая, но отрезана от нас — например, соседний кусок этажа,
    в который ведёт лестница, а не коридор. }
  AReason := 'туда не пройти: нет дороги';
end;

end.
