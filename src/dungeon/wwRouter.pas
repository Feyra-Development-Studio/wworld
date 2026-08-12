unit wwRouter;
{ Прокладка коридоров: A* по 8 направлениям (диагонали разрешены) кистью
  шириной 1..3 клетки. Кисть ставится только туда, где сама клетка и весь
  её 8-окрестный периметр свободны либо принадлежат разрешённому набору
  структур — поэтому непреднамеренное касание/наложение невозможно
  по построению, а не проверкой постфактум.
  Перебор соседей и разрешение равных приоритетов строго упорядочены,
  поэтому маршрут воспроизводим по seed. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, wwCore, wwGrid;

type
  TWwRouter = class
  private
    FGrid: TWwGrid;
    FW, FH, FSize: Integer;
    FG, FF, FPrev, FSteps: array of Integer;
    FState: array of Byte;
    FHeap: array of Integer;
    FHeapN: Integer;
    FAllowed: TWwIntList;
    FBrush: Integer;
    FGoalOwner, FGoalX, FGoalY: Integer;
    FMaxSteps: Integer;
    FPath: TWwPointList;
    FDirX, FDirY: array[0..7] of Integer;
    procedure Reset;
    procedure HeapPush(ANode: Integer);
    function HeapPop: Integer;
    function Better(ANodeA, ANodeB: Integer): Boolean;
    function Heuristic(AX, AY: Integer): Integer;
    function CanStand(AX, AY: Integer): Boolean;
    procedure BuildPath(ANode: Integer);
  public
    constructor Create(AGrid: TWwGrid);
    destructor Destroy; override;
    procedure BrushCells(ACX, ACY: Integer; AOut: TWwPointList);
    function Route(AStartX, AStartY, AGoalOwner, AGoalX, AGoalY,
      ABrush, AMaxSteps: Integer; AAllowed: TWwIntList): Boolean;
    property Path: TWwPointList read FPath;
  end;

implementation

constructor TWwRouter.Create(AGrid: TWwGrid);
begin
  inherited Create;
  FGrid := AGrid;
  FW := AGrid.W;
  FH := AGrid.H;
  FSize := FW * FH;
  SetLength(FG, FSize);
  SetLength(FF, FSize);
  SetLength(FPrev, FSize);
  SetLength(FSteps, FSize);
  SetLength(FState, FSize);
  SetLength(FHeap, FSize + 8);
  FPath := TWwPointList.Create;
  FDirX[0] :=  1; FDirY[0] :=  0;
  FDirX[1] :=  1; FDirY[1] :=  1;
  FDirX[2] :=  0; FDirY[2] :=  1;
  FDirX[3] := -1; FDirY[3] :=  1;
  FDirX[4] := -1; FDirY[4] :=  0;
  FDirX[5] := -1; FDirY[5] := -1;
  FDirX[6] :=  0; FDirY[6] := -1;
  FDirX[7] :=  1; FDirY[7] := -1;
end;

destructor TWwRouter.Destroy;
begin
  FPath.Free;
  inherited Destroy;
end;

procedure TWwRouter.Reset;
var
  i: Integer;
begin
  for i := 0 to FSize - 1 do
  begin
    FState[i] := 0;
    FG[i] := MaxInt;
    FF[i] := MaxInt;
    FPrev[i] := -1;
    FSteps[i] := 0;
  end;
  FHeapN := 0;
  FPath.Clear;
end;

function TWwRouter.Better(ANodeA, ANodeB: Integer): Boolean;
begin
  if FF[ANodeA] <> FF[ANodeB] then
    Result := FF[ANodeA] < FF[ANodeB]
  else
    Result := ANodeA < ANodeB;
end;

procedure TWwRouter.HeapPush(ANode: Integer);
var
  i, p, t: Integer;
begin
  FHeap[FHeapN] := ANode;
  i := FHeapN;
  Inc(FHeapN);
  while i > 0 do
  begin
    p := (i - 1) div 2;
    if Better(FHeap[i], FHeap[p]) then
    begin
      t := FHeap[i]; FHeap[i] := FHeap[p]; FHeap[p] := t;
      i := p;
    end
    else
      Break;
  end;
end;

function TWwRouter.HeapPop: Integer;
var
  i, l, r, m, t: Integer;
begin
  Result := FHeap[0];
  Dec(FHeapN);
  FHeap[0] := FHeap[FHeapN];
  i := 0;
  while True do
  begin
    l := 2 * i + 1;
    r := l + 1;
    m := i;
    if (l < FHeapN) and Better(FHeap[l], FHeap[m]) then m := l;
    if (r < FHeapN) and Better(FHeap[r], FHeap[m]) then m := r;
    if m = i then Break;
    t := FHeap[i]; FHeap[i] := FHeap[m]; FHeap[m] := t;
    i := m;
  end;
end;

function TWwRouter.Heuristic(AX, AY: Integer): Integer;
var
  dx, dy, lo, hi: Integer;
begin
  dx := Abs(AX - FGoalX);
  dy := Abs(AY - FGoalY);
  if dx < dy then begin lo := dx; hi := dy; end else begin lo := dy; hi := dx; end;
  Result := 10 * (hi - lo) + 14 * lo;
end;

{ Кисть ранга: 1 -> 1x1, 2 -> 2x2, 3 -> 3x3 с центром в (cx,cy). }
procedure TWwRouter.BrushCells(ACX, ACY: Integer; AOut: TWwPointList);
var
  dx, dy: Integer;
begin
  AOut.Clear;
  case FBrush of
    1: AOut.Add(ACX, ACY);
    2:
      for dy := 0 to 1 do
        for dx := 0 to 1 do
          AOut.Add(ACX + dx, ACY + dy);
  else
    for dy := -1 to 1 do
      for dx := -1 to 1 do
        AOut.Add(ACX + dx, ACY + dy);
  end;
end;

function TWwRouter.CanStand(AX, AY: Integer): Boolean;
var
  dx, dy, x0, y0, x1, y1: Integer;
begin
  case FBrush of
    1: begin x0 := 0; y0 := 0; x1 := 0; y1 := 0; end;
    2: begin x0 := 0; y0 := 0; x1 := 1; y1 := 1; end;
  else
    begin x0 := -1; y0 := -1; x1 := 1; y1 := 1; end;
  end;
  for dy := y0 to y1 do
    for dx := x0 to x1 do
      if not FGrid.CanOccupy(AX + dx, AY + dy, FAllowed) then
      begin
        Result := False;
        Exit;
      end;
  Result := True;
end;

procedure TWwRouter.BuildPath(ANode: Integer);
var
  n, i, c: Integer;
  xs, ys: array of Integer;
begin
  n := 0;
  c := ANode;
  while c <> -1 do
  begin
    Inc(n);
    c := FPrev[c];
  end;
  SetLength(xs, n);
  SetLength(ys, n);
  c := ANode;
  i := n - 1;
  while c <> -1 do
  begin
    xs[i] := c mod FW;
    ys[i] := c div FW;
    Dec(i);
    c := FPrev[c];
  end;
  FPath.Clear;
  for i := 0 to n - 1 do
    FPath.Add(xs[i], ys[i]);
end;

function TWwRouter.Route(AStartX, AStartY, AGoalOwner, AGoalX, AGoalY,
  ABrush, AMaxSteps: Integer; AAllowed: TWwIntList): Boolean;
var
  startNode, cur, nx, ny, nn, d, step, ng, prevDir, curDir: Integer;
begin
  FBrush := ABrush;
  FAllowed := AAllowed;
  FGoalOwner := AGoalOwner;
  FGoalX := AGoalX;
  FGoalY := AGoalY;
  FMaxSteps := AMaxSteps;
  Reset;

  if not FGrid.InBounds(AStartX, AStartY) then
  begin
    Result := False;
    Exit;
  end;
  if not CanStand(AStartX, AStartY) then
  begin
    Result := False;
    Exit;
  end;

  startNode := AStartY * FW + AStartX;
  FG[startNode] := 0;
  FF[startNode] := Heuristic(AStartX, AStartY);
  FSteps[startNode] := 0;
  FState[startNode] := 1;
  HeapPush(startNode);

  while FHeapN > 0 do
  begin
    cur := HeapPop;
    if FState[cur] = 2 then Continue;
    FState[cur] := 2;

    if (FGrid.OwnerAt(cur mod FW, cur div FW) = FGoalOwner) and (FSteps[cur] > 0) then
    begin
      BuildPath(cur);
      Result := True;
      Exit;
    end;

    step := FSteps[cur];
    if step >= FMaxSteps then Continue;

    if FPrev[cur] = -1 then
      prevDir := -1
    else
      prevDir := (cur mod FW - FPrev[cur] mod FW) * 10 + (cur div FW - FPrev[cur] div FW);

    for d := 0 to 7 do
    begin
      nx := (cur mod FW) + FDirX[d];
      ny := (cur div FW) + FDirY[d];
      if not FGrid.InBounds(nx, ny) then Continue;
      nn := ny * FW + nx;
      if FState[nn] = 2 then Continue;
      if not CanStand(nx, ny) then Continue;

      if (FDirX[d] <> 0) and (FDirY[d] <> 0) then ng := FG[cur] + 14 else ng := FG[cur] + 10;
      curDir := FDirX[d] * 10 + FDirY[d];
      if (prevDir <> -1) and (curDir <> prevDir) then Inc(ng, 4);

      if ng < FG[nn] then
      begin
        FG[nn] := ng;
        FF[nn] := ng + Heuristic(nx, ny);
        FPrev[nn] := cur;
        FSteps[nn] := step + 1;
        FState[nn] := 1;
        HeapPush(nn);
      end;
    end;
  end;

  Result := False;
end;

end.
