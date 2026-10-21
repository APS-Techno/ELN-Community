unit unit_TreeLook;

{ TTreeLook owns OnMeasureItem, OnAfterItemPaint, header owner-draw events and
  WindowProc. The host must not replace them and must free the look before the tree.
  After StretchLastColumn it also owns OnHeaderDragged, Header.AutoSizeIndex and
  hoAutoResize, and the host reads and sets column widths through ColumnWidth and
  SetColumnWidth. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.Types, System.SysUtils,
  System.Classes, Vcl.Graphics, Vcl.Controls,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.BaseTree, VirtualTrees.Header;

type
  TTreeRowColorFunc = reference to function(Node: PVirtualNode): TColor;
  TTreeNodePredicate = reference to function(Node: PVirtualNode): Boolean;
  TTreeNodeProc = reference to procedure(Node: PVirtualNode);

  TTreeLook = class
  private
    FTree: TVirtualStringTree;
    FRowColor: TTreeRowColorFunc;
    FIsContainer: TTreeNodePredicate;
    FOnFocus: TTreeNodeProc;
    FOldWndProc: TWndMethod;
    FHoverNode: PVirtualNode;   // compared only, never dereferenced: may be stale
    FHoverAction: Integer;
    FHoverRowRect: TRect;
    FActionDown: Boolean;
    // The tree's own metrics at 96 PPI, taken once: every apply starts here.
    FBaseFont, FBaseHeaderFont, FBaseHeaderHeight: Integer;
    FBaseIndent: Integer;
    FStretchColumn: TColumnIndex;
    FStretchWidth, FStretchPPI: Integer;
    function NaturalRowHeight(out TextHeight: Integer): Integer;
    procedure WndProc(var Message: Winapi.Messages.TMessage);
    function ShowsActions(Node: PVirtualNode): Boolean;
    function ActionHit(const P: TPoint; out Node: PVirtualNode): Integer;
    procedure UpdateHover(const P: TPoint);
    procedure SetHover(Node: PVirtualNode; Action: Integer);
    procedure RunAction(Node: PVirtualNode; Action: Integer);
    procedure MeasureItem(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; var NodeHeight: TDimension);
    procedure AfterItemPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; ItemRect: TRect);
    procedure HeaderDrawQueryElements(Sender: TVTHeader;
      var PaintInfo: THeaderPaintInfo; var Elements: THeaderPaintElements);
    procedure AdvancedHeaderDraw(Sender: TVTHeader;
      var PaintInfo: THeaderPaintInfo; const Elements: THeaderPaintElements);
    procedure HeaderDragged(Sender: TVTHeader; Column: TColumnIndex;
      OldPosition: Integer);
    function Background: TColor;
    function IsDark: Boolean;
    function LineLeft(ALevel: Integer): Integer;
    function LineNodes(Node: PVirtualNode): TArray<PVirtualNode>;
    function EndsBlock(Node, Container: PVirtualNode): Boolean;
  public
    constructor Create(ATree: TVirtualStringTree; ARowColor: TTreeRowColorFunc;
      AIsContainer: TTreeNodePredicate; AOnFocus: TTreeNodeProc);
    destructor Destroy; override;
    /// Call before Tree.Clear: forgets the hovered row.
    procedure ClearHover;
    procedure ApplyAppearance;
    /// The last visible column fills the width the other columns leave free.
    /// Call again after a column is shown or hidden.
    procedure StretchLastColumn;
    /// The stretched column reports and keeps the width it has when not stretched.
    function ColumnWidth(Column: TColumnIndex): Integer;
    procedure SetColumnWidth(Column: TColumnIndex; Width: Integer);
    class procedure ApplyAll;
    function PPI: Integer;
    function HeaderGap(Node: PVirtualNode): Integer;
    function RowTint(Node: PVirtualNode): TColor;
    function RowBackground(Node: PVirtualNode): TColor;
    procedure BeforeCellPaint(TargetCanvas: TCanvas; Node: PVirtualNode;
      CellPaintMode: TVTCellPaintMode; const CellRect: TRect;
      var ContentRect: TRect);
    /// From the tree's OnAfterCellPaint, first thing. Moves CellRect.Top below
    /// a header's gap. True when it drew the action pill in this cell - the
    /// caller then skips its own right-aligned badges there.
    function AfterCellPaint(TargetCanvas: TCanvas; Node: PVirtualNode;
      Column: TColumnIndex; var CellRect: TRect): Boolean;
    function LineColors(Node: PVirtualNode): TArray<TColor>;
    procedure PaintText(TargetCanvas: TCanvas; Node: PVirtualNode;
      Column: TColumnIndex);
  end;

implementation

uses
  System.Math, System.Generics.Collections, Vcl.Forms, unit_TreeBadges,
  unit_TreeAppearance;

var
  GLooks: TList<TTreeLook>;   


constructor TTreeLook.Create(ATree: TVirtualStringTree;
  ARowColor: TTreeRowColorFunc; AIsContainer: TTreeNodePredicate;
  AOnFocus: TTreeNodeProc);
begin
  inherited Create;
  FTree := ATree;
  FRowColor := ARowColor;
  FIsContainer := AIsContainer;
  FOnFocus := AOnFocus;
  FHoverAction := -1;
  FStretchColumn := NoColumn;

  FTree.TreeOptions.MiscOptions := FTree.TreeOptions.MiscOptions + [toVariableNodeHeight];
  // Row height is ApplyAppearance's: VirtualTree must not reset it to its own
  // choice whenever the window is made or the font changes.
  FTree.TreeOptions.AutoOptions := FTree.TreeOptions.AutoOptions - [toAutoChangeScale];
  FTree.OnMeasureItem := MeasureItem;
  FTree.OnAfterItemPaint := AfterItemPaint;
  FTree.TreeOptions.PaintOptions := FTree.TreeOptions.PaintOptions - [toShowTreeLines];
  FTree.Header.Options := FTree.Header.Options + [hoOwnerDraw];
  FTree.OnHeaderDrawQueryElements := HeaderDrawQueryElements;
  FTree.OnAdvancedHeaderDraw := AdvancedHeaderDraw;
  // Own font from here on: a following tree font would drop the semibold
  // face whenever ApplyAppearance resizes the tree font.
  FTree.Header.ParentFont := False;
  if SameText(FTree.Header.Font.Name, 'Segoe UI') then
    FTree.Header.Font.Name := 'Segoe UI Semibold';

  FTree.ShowHint := True;
  FTree.ParentShowHint := False;
  FOldWndProc := FTree.WindowProc;
  FTree.WindowProc := WndProc;

  FBaseFont := MulDiv(FTree.Font.Height, 96, FTree.CurrentPPI);
  FBaseHeaderFont := MulDiv(FTree.Header.Font.Height, 96, FTree.CurrentPPI);
  FBaseHeaderHeight := MulDiv(Integer(FTree.Header.Height), 96, FTree.CurrentPPI);
  FBaseIndent := MulDiv(Integer(FTree.Indent), 96, FTree.CurrentPPI);
  if not Assigned(GLooks) then
    GLooks := TList<TTreeLook>.Create;
  GLooks.Add(Self);
  ApplyAppearance;
end;

destructor TTreeLook.Destroy;
begin
  if Assigned(GLooks) then
    GLooks.Remove(Self);
  FTree.WindowProc := FOldWndProc;
  FTree.OnAfterItemPaint := nil;
  FTree.OnHeaderDragged := nil;
  inherited;
end;

function TTreeLook.Background: TColor;
begin
  Result := TreeRowBackground(FTree, nil);
end;

function TTreeLook.IsDark: Boolean;
begin
  Result := RelativeLuminance(Background) < 0.3;
end;

procedure TTreeLook.ClearHover;
begin
  SetHover(nil, -1);
end;

// The height VirtualTree's own AutoScale would pick: a line of text plus the
// text margin, or an icon plus its margin. Measured off-screen, so it never
// forces the tree's window into existence.
function TTreeLook.NaturalRowHeight(out TextHeight: Integer): Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(FTree.Font);
    TextHeight := B.Canvas.TextHeight('Tg');
  finally
    B.Free;
  end;
  Result := TextHeight + Integer(FTree.TextMargin);
  if Assigned(FTree.Images) then
    Result := Max(Result, FTree.Images.Height +
      Max(1, MulDiv(1, FTree.CurrentPPI, 96)));
end;

procedure TTreeLook.ApplyAppearance;
var
  PPIOf, TextHeight, Row: Integer;
  N: PVirtualNode;
begin
  PPIOf := FTree.CurrentPPI;
  FTree.BeginUpdate;
  try
    FTree.Font.Height := MulDiv(Appearance.Scaled(FBaseFont), PPIOf, 96);
    FTree.Header.Font.Height := MulDiv(Appearance.Scaled(FBaseHeaderFont), PPIOf, 96);
    FTree.Header.Height := MulDiv(Appearance.Scaled(FBaseHeaderHeight), PPIOf, 96);
    FTree.Indent := MulDiv(Appearance.Scaled(FBaseIndent), PPIOf, 96);
    Row := Appearance.Spaced(NaturalRowHeight(TextHeight));
    FTree.DefaultNodeHeight := Max(Row, TextHeight + 2);
    // A new default height leaves existing rows as they were: give them the
    // new one and let MeasureItem size the top-level headers again. NoInit:
    // initialising would make the item tree load children from the DB.
    N := FTree.GetFirstNoInit;
    while Assigned(N) do
    begin
      N.States := N.States - [vsHeightMeasured];
      FTree.NodeHeight[N] := FTree.DefaultNodeHeight;
      N := FTree.GetNextNoInit(N);
    end;
  finally
    FTree.EndUpdate;
  end;
  FTree.Invalidate;
end;

class procedure TTreeLook.ApplyAll;
var
  Look: TTreeLook;
begin
  if Assigned(GLooks) then
    for Look in GLooks do
      Look.ApplyAppearance;
end;

function TTreeLook.PPI: Integer;
begin
  Result := MulDiv(FTree.CurrentPPI, Appearance.Scale, 100);
end;

procedure TTreeLook.StretchLastColumn;
var
  Columns: TVirtualTreeColumns;
  Last, Previous: TColumnIndex;
  PreviousWidth: Integer;
begin
  Columns := FTree.Header.Columns;
  Last := Columns.GetLastVisibleColumn;
  if Last = NoColumn then Exit;
  if (Last = FStretchColumn) and (hoAutoResize in FTree.Header.Options) then Exit;
  Previous := FStretchColumn;
  PreviousWidth := ColumnWidth(Previous);
  FStretchColumn := Last;
  FStretchWidth := Columns[Last].Width;
  FStretchPPI := FTree.CurrentPPI;
  FTree.Header.AutoSizeIndex := Last;
  if not (hoAutoResize in FTree.Header.Options) then
    FTree.Header.Options := FTree.Header.Options + [hoAutoResize];
  FTree.OnHeaderDragged := HeaderDragged;
  if Previous <> NoColumn then
    Columns[Previous].Width := PreviousWidth;
end;

procedure TTreeLook.HeaderDragged(Sender: TVTHeader; Column: TColumnIndex;
  OldPosition: Integer);
begin
  StretchLastColumn;
end;

function TTreeLook.ColumnWidth(Column: TColumnIndex): Integer;
begin
  if Column = NoColumn then
    Result := 0
  else if Column = FStretchColumn then
    Result := MulDiv(FStretchWidth, FTree.CurrentPPI, FStretchPPI)
  else
    Result := FTree.Header.Columns[Column].Width;
end;

procedure TTreeLook.SetColumnWidth(Column: TColumnIndex; Width: Integer);
begin
  if Column = FStretchColumn then
  begin
    FStretchWidth := Width;
    FStretchPPI := FTree.CurrentPPI;
  end
  else
    FTree.Header.Columns[Column].Width := Width;
end;


procedure TTreeLook.MeasureItem(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
  Node: PVirtualNode; var NodeHeight: TDimension);
var
  Gap, Img: Integer;
begin
  if Sender.GetNodeLevel(Node) <> 0 then Exit;
  Gap := MulDiv(8, PPI, 96);
  Img := 16;
  if Assigned(FTree.Images) then
    Img := FTree.Images.Height;
  NodeHeight := FTree.DefaultNodeHeight + Gap;
  Node.Align := Round(100 * (Gap + (FTree.DefaultNodeHeight - Img) / 2) /
    (Gap + FTree.DefaultNodeHeight - Img));
end;

function TTreeLook.HeaderGap(Node: PVirtualNode): Integer;
begin
  Result := 0;
  if Assigned(Node) and (FTree.GetNodeLevel(Node) = 0) then
    Result := Max(0, Integer(FTree.NodeHeight[Node]) - Integer(FTree.DefaultNodeHeight));
end;

function TTreeLook.RowTint(Node: PVirtualNode): TColor;
begin
  Result := MixColor(Background, FRowColor(Node), Appearance.TintFactor(IsDark));
end;

function TTreeLook.RowBackground(Node: PVirtualNode): TColor;
begin
  if vsSelected in Node.States then
    Result := TreeRowBackground(FTree, Node)
  else
    Result := RowTint(Node);
end;

function TTreeLook.LineNodes(Node: PVirtualNode): TArray<PVirtualNode>;
var
  P: PVirtualNode;
begin
  SetLength(Result, FTree.GetNodeLevel(Node) + 1);
  P := Node;
  if not FIsContainer(Node) then
  begin
    SetLength(Result, Length(Result) - 1);
    P := FTree.NodeParent[P];
  end;
  while Assigned(P) do
  begin
    Result[FTree.GetNodeLevel(P)] := P;
    P := FTree.NodeParent[P];
  end;
end;

function TTreeLook.LineColors(Node: PVirtualNode): TArray<TColor>;
var
  Nodes: TArray<PVirtualNode>;
  I: Integer;
begin
  Nodes := LineNodes(Node);
  SetLength(Result, Length(Nodes));
  for I := 0 to High(Nodes) do
    Result[I] := FRowColor(Nodes[I]);
end;

function TTreeLook.EndsBlock(Node, Container: PVirtualNode): Boolean;
var
  Next: PVirtualNode;
begin
  Result := False;
  if Node = Container then Exit;   
  Next := FTree.GetNextVisible(Node);
  Result := not Assigned(Next) or not FTree.HasAsParent(Next, Container);
end;

function TTreeLook.LineLeft(ALevel: Integer): Integer;
begin
  Result := FTree.Header.Columns[FTree.Header.MainColumn].Left + FTree.Margin +
    ALevel * Integer(FTree.Indent);
end;

procedure TTreeLook.BeforeCellPaint(TargetCanvas: TCanvas; Node: PVirtualNode;
  CellPaintMode: TVTCellPaintMode; const CellRect: TRect;
  var ContentRect: TRect);
var
  Gap: Integer;
begin
  Gap := HeaderGap(Node);
  // Text is centred in ContentRect: keep header text on the band.
  Inc(ContentRect.Top, Gap);
  if CellPaintMode <> cpmPaint then Exit;
  TargetCanvas.Brush.Style := bsSolid;
  TargetCanvas.Brush.Color := RowTint(Node);
  TargetCanvas.FillRect(Rect(CellRect.Left, CellRect.Top + Gap,
    CellRect.Right, CellRect.Bottom));
end;

function TTreeLook.AfterCellPaint(TargetCanvas: TCanvas; Node: PVirtualNode;
  Column: TColumnIndex; var CellRect: TRect): Boolean;
var
  Gap, D, X, W, Y0: Integer;
  Lines: TArray<PVirtualNode>;
begin
  Result := False;
  TargetCanvas.Brush.Style := bsSolid;
  Gap := HeaderGap(Node);
  Inc(CellRect.Top, Gap);
  if Column <> FTree.Header.MainColumn then Exit;

  Lines := LineNodes(Node);
  W := Max(2, MulDiv(2, PPI, 96));
  Y0 := (CellRect.Top + CellRect.Bottom - W) div 2;   
  for D := 0 to High(Lines) do
  begin
    X := LineLeft(D);
    TargetCanvas.Brush.Color := FRowColor(Lines[D]);
    if EndsBlock(Node, Lines[D]) then
    begin
      TargetCanvas.FillRect(Rect(X, CellRect.Top, X + W, Y0 + W));
      TargetCanvas.FillRect(Rect(X, Y0, X + Integer(FTree.Indent) div 2, Y0 + W));
    end
    else
      TargetCanvas.FillRect(Rect(X, CellRect.Top, X + W, CellRect.Bottom));
  end;

  if ShowsActions(Node) then
  begin
    if Node = FHoverNode then
      DrawTreeActions(TargetCanvas, CellRect, PPI, RowBackground(Node), FHoverAction)
    else
      DrawTreeActions(TargetCanvas, CellRect, PPI, RowBackground(Node), -1);
    Result := True;
  end;
end;

procedure TTreeLook.AfterItemPaint(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
  Node: PVirtualNode; ItemRect: TRect);
var
  Gap, ColumnsRight: Integer;
begin
  TargetCanvas.Brush.Style := bsSolid;
  TargetCanvas.Brush.Color := Background;
  // Cell paint events are column-clipped; selection also fills unused row width.
  if FTree.Header.UseColumns then
  begin
    ColumnsRight := FTree.Header.Columns.TotalWidth;
    if ColumnsRight < ItemRect.Right then
      TargetCanvas.FillRect(Rect(ColumnsRight, ItemRect.Top, ItemRect.Right,
        ItemRect.Bottom));
  end;
  Gap := HeaderGap(Node);
  if Gap > 0 then
    TargetCanvas.FillRect(Rect(ItemRect.Left, ItemRect.Top, ItemRect.Right,
      ItemRect.Top + Gap));
end;

procedure TTreeLook.PaintText(TargetCanvas: TCanvas; Node: PVirtualNode;
  Column: TColumnIndex);
begin
  if (Column <> FTree.Header.MainColumn) or (HeaderGap(Node) = 0) then Exit;
  if SameText(TargetCanvas.Font.Name, 'Segoe UI') then
    TargetCanvas.Font.Name := 'Segoe UI Semibold'
  else
    TargetCanvas.Font.Style := TargetCanvas.Font.Style + [fsBold];
end;


procedure TTreeLook.HeaderDrawQueryElements(Sender: TVTHeader;
  var PaintInfo: THeaderPaintInfo; var Elements: THeaderPaintElements);
begin
  Elements := [hpeBackground];
end;

procedure TTreeLook.AdvancedHeaderDraw(Sender: TVTHeader;
  var PaintInfo: THeaderPaintInfo; const Elements: THeaderPaintElements);
var
  Fill, Border: TColor;
  R: TRect;
  C: TCanvas;
begin
  if not (hpeBackground in Elements) then Exit;
  if IsDark then
  begin
    Fill := MixColor(Background, BADGE_SLATE, 0.22);
    Border := MixColor(Background, BADGE_SLATE, 0.45);
  end
  else
  begin
    Fill := MixColor(Background, BADGE_SLATE, 0.09);
    Border := MixColor(Background, BADGE_SLATE, 0.25);
  end;
  C := PaintInfo.TargetCanvas;
  R := PaintInfo.PaintRectangle;
  C.Brush.Style := bsSolid;
  C.Brush.Color := Fill;
  C.FillRect(R);
  C.Brush.Color := Border;
  C.FillRect(Rect(R.Left, R.Bottom - 1, R.Right, R.Bottom));
  if Assigned(PaintInfo.Column) then
    C.FillRect(Rect(R.Right - 1, R.Top + 4, R.Right, R.Bottom - 4));
end;


// Below VirtualTree's own mouse handling: a click on a pill button is
// swallowed, so it neither selects the row, nor opens it on double-click,
// nor starts a drag.
procedure TTreeLook.WndProc(var Message: Winapi.Messages.TMessage);
var
  Node: PVirtualNode;
  Action: Integer;
begin
  case Message.Msg of
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
      begin
        Action := ActionHit(Point(TWMMouse(Message).XPos,
          TWMMouse(Message).YPos), Node);
        // Reset on every press: an up released outside the tree never came.
        FActionDown := Action >= 0;
        if FActionDown then
        begin
          RunAction(Node, Action);
          Message.Result := 0;
          Exit;
        end;
      end;
    WM_LBUTTONUP:
      if FActionDown then
      begin
        FActionDown := False;
        Message.Result := 0;
        Exit;
      end;
    CM_MOUSELEAVE:
      SetHover(nil, -1);
  end;

  FOldWndProc(Message);

  case Message.Msg of
    WM_MOUSEMOVE:
      if TWMMouse(Message).Keys and MK_LBUTTON = 0 then
        UpdateHover(Point(TWMMouse(Message).XPos, TWMMouse(Message).YPos));
    WM_LBUTTONUP:
      // The click may have selected a row whose pill now sits under the mouse.
      UpdateHover(Point(TWMMouse(Message).XPos, TWMMouse(Message).YPos));
    WM_MOUSEWHEEL, WM_VSCROLL, WM_HSCROLL, WM_KEYDOWN:
      // The rows or the focused row moved under a still mouse.
      UpdateHover(FTree.ScreenToClient(Mouse.CursorPos));
  end;
end;

function TTreeLook.ShowsActions(Node: PVirtualNode): Boolean;
begin
  Result := Assigned(Node) and (Node = FTree.FocusedNode) and
    FTree.Selected[Node] and FIsContainer(Node) and FTree.HasChildren[Node];
end;

function TTreeLook.ActionHit(const P: TPoint; out Node: PVirtualNode): Integer;
var
  R: TRect;
begin
  Result := -1;
  Node := FTree.GetNodeAt(P.X, P.Y);
  if not ShowsActions(Node) then
  begin
    Node := nil;
    Exit;
  end;
  R := FTree.GetDisplayRect(Node, FTree.Header.MainColumn, False);
  Inc(R.Top, HeaderGap(Node));   
  Result := TreeActionAt(R, PPI, P);
end;

procedure TTreeLook.UpdateHover(const P: TPoint);
var
  Node: PVirtualNode;
  Action: Integer;
begin
  Action := ActionHit(P, Node);
  SetHover(Node, Action);
end;

procedure TTreeLook.SetHover(Node: PVirtualNode; Action: Integer);
const
  HINTS: array[0..TREE_ACTION_COUNT - 1] of string = (
    'Collapse all below', 'Expand all below',
    'Focus: collapse everything else');
var
  R: TRect;
  NewHint: string;
begin
  if (Node = FHoverNode) and (Action = FHoverAction) then Exit;

  // Repaint the old and the new row by rectangle - the old node pointer may
  // already be freed.
  if FTree.HandleAllocated and not FHoverRowRect.IsEmpty then
    InvalidateRect(FTree.Handle, @FHoverRowRect, False);
  FHoverNode := Node;
  FHoverAction := Action;
  FHoverRowRect := TRect.Empty;
  if Assigned(Node) then
  begin
    R := FTree.GetDisplayRect(Node, FTree.Header.MainColumn, False);
    FHoverRowRect := Rect(0, R.Top, FTree.ClientWidth, R.Bottom);
    if FTree.HandleAllocated then
      InvalidateRect(FTree.Handle, @FHoverRowRect, False);
  end;

  if Action >= 0 then
    NewHint := HINTS[Action]
  else
    NewHint := '';
  if NewHint <> FTree.Hint then
  begin
    FTree.Hint := NewHint;
    Application.CancelHint;   
  end;
end;

procedure TTreeLook.RunAction(Node: PVirtualNode; Action: Integer);
var
  P: PVirtualNode;
begin
  FTree.BeginUpdate;
  try
    case Action of
      TREE_ACTION_COLLAPSE:
        FTree.FullCollapse(Node);
      TREE_ACTION_EXPAND:
        FTree.FullExpand(Node);
      TREE_ACTION_FOCUS:
        begin
          FTree.FullCollapse;
          P := Node;
          while Assigned(P) do
          begin
            FTree.Expanded[P] := True;
            P := FTree.NodeParent[P];
          end;
        end;
    end;
  finally
    FTree.EndUpdate;
  end;

  if Action = TREE_ACTION_FOCUS then
  begin
    FTree.ClearSelection;
    FTree.FocusedNode := Node;
    FTree.Selected[Node] := True;
    FTree.ScrollIntoView(Node, False);
    if Assigned(FOnFocus) then
      FOnFocus(Node);   
  end;

  UpdateHover(FTree.ScreenToClient(Mouse.CursorPos));
end;

initialization

finalization
  FreeAndNil(GLooks);

end.
