function RuleExists(Board: IPCB_Board, const RuleName: WideString): Boolean;
var
  Iterator: IPCB_BoardIterator;
  Rule    : IPCB_Rule;
begin
  Result := False;

  // Create an iterator for rules
  Iterator := Board.BoardIterator_Create;
  Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
  Iterator.AddFilter_LayerSet(AllLayers);
  Iterator.AddFilter_Method(eProcessAll);

  Rule := Iterator.FirstPCBObject;
  while Rule <> Nil do
  begin
    if Rule.Name = RuleName then
    begin
      Result := True;
      Break;
    end;
    Rule := Iterator.NextPCBObject;
  end;

  Board.BoardIterator_Destroy(Iterator);
end;

Function RuleWidthChange(Board: IPCB_Board);
var
  RuleWidth : IPCB_Rule;
  P          : IPCB_MaxMinWidthConstraint;
  MaxLimit   : TCoord;
  MinLimit   : TCoord;
  L          : TLayer;
  RuleName   : String;
begin
    RuleName := 'Custom Width Rule';
    if RuleExists(Board, RuleName) then
    begin                                                    
      Exit;
    end;
    P := PCBServer.PCBRuleFactory(eRule_MaxMinWidth);

    // Set values
    P.NetScope  := eNetScope_AnyNet;
    P.LayerKind := eRuleLayerKind_SameLayer;
    For L := MinLayer To MaxLayer Do
    Begin
        P.MaxWidth    [L] := MMsToCoord(2);;
        P.MinWidth    [L] := MMsToCoord(0.2);;
    End;

    P.Name    := RuleName;
    P.Comment := RuleName;

    // Add the rule into the Board
    Board.AddPCBObject(P);
end;


Function DoesUnionIndexExist(Board: IPCB_Board; Index : Integer) : Boolean;
Var
   Iterator  : IPCB_BoardIterator;
   Primitive : IPCB_Primitive;
Begin
    Result := False;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(AllPrimitives);

    Primitive := Iterator.FirstPCBObject;
    While (Primitive <> Nil) Do
    Begin
        If Primitive.UnionIndex = Index Then
        Begin
           Result := True;
           Break;
        End;
        Primitive := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);
End;

Function MakeHole(Board: IPCB_Board; HoleSize : TCoord; CenterX: TCoord; CenterY : TCoord);
var
  Pad         : IPCB_Pad;
  Arc         : IPCB_Arc;
  counter     : Integer;
  Layercounter: Integer;
  Layer       : array[1..4] of TLayer;
  UnionIndex  : Integer;

  procedure AddUnionArc(Board: IPCB_Board; Layer: TLayer; Radius, LineWidth: TCoord;
                        CenterX, CenterY: TCoord; StartAngle, EndAngle: Double;
                        UnionIndex: Integer);
  var
    A: IPCB_Arc;
  begin
    A := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
    A.Layer := Layer;
    A.LineWidth := LineWidth;
    A.Radius := Radius;
    A.XCenter := CenterX;
    A.YCenter := CenterY;
    A.StartAngle := StartAngle;
    A.EndAngle := EndAngle;
    A.UnionIndex := UnionIndex;
    Board.AddPCBObject(A);
  end;

Begin
  // Generate a unique union index for arcs
  Repeat
    UnionIndex := GetHashID_ForString(GetWorkSpace.DM_GenerateUniqueID);
  Until not DoesUnionIndexExist(Board, UnionIndex);

  // Create decorative arcs in union
  Layer[1] := eTopLayer;
  Layer[2] := eBottomLayer;
  Layer[3] := eTopSolder;
  Layer[4] := eBottomSolder;
  for Layercounter := 1 to 4 do
    for counter := 0 to 3 do
      AddUnionArc(Board, Layer[Layercounter], HoleSize * 0.7, HoleSize * 0.23,
                  CenterX, CenterY, 90 * counter + 12, 90 * counter + 78, UnionIndex);

  // Top overlay arc
  Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
  Arc.Layer := eTopOverlay;
  Arc.LineWidth := MMsToCoord(0.15);
  Arc.Radius := HoleSize * 0.9;
  Arc.XCenter := CenterX;
  Arc.YCenter := CenterY;
  Arc.StartAngle := 0;
  Arc.EndAngle := 360;
  Arc.UnionIndex := UnionIndex;
  Board.AddPCBObject(Arc);

  // Bottom overlay arc
  Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
  Arc.Layer := eBottomOverlay;
  Arc.LineWidth := MMsToCoord(0.15);
  Arc.Radius := HoleSize * 0.9;
  Arc.XCenter := CenterX;
  Arc.YCenter := CenterY;
  Arc.StartAngle := 0;
  Arc.EndAngle := 360;
  Arc.UnionIndex := UnionIndex;
  Board.AddPCBObject(Arc);

  // Create the pad with hole
  Pad := PCBServer.PCBObjectFactory(ePadObject, eNoDimension, eCreate_Default);
  Pad.X := CenterX;
  Pad.Y := CenterY;
  Pad.HoleSize := HoleSize;
  Pad.TopXSize := HoleSize;
  Pad.TopYSize := HoleSize;
  Pad.BotXSize := HoleSize;
  Pad.BotYSize := HoleSize;
  Pad.Layer := eMultiLayer;
  Pad.UnionIndex := UnionIndex;
  Board.AddPCBObject(Pad);
End;


procedure TPCBCreator.CreateClick(Sender: TObject);
var
    Board       : IPCB_Board;
    Track       : IPCB_Track;
    Arc         : IPCB_Arc;
    Pad         : IPCB_Pad;
    CenterX     : TCoord;
    CenterY     : TCoord;
    BoardWidth  : TCoord;
    BoardHeight : TCoord;
    FilletRadius: TCoord;
    HoleSize    : TCoord;
    HoleMargin  : TCoord;
    PadSize     : TCoord;
    LineWidth   : TCoord;
    L           : TLayer;
    Obj         : IPCB_Primitive;
    Iterator    : IPCB_BoardIterator;
    sWidth, sHeight, sFilletRadius, sHoleSize, sHoleMargin : string;
    dWidth, dHeight, dFilletRadius, dHoleSize, dHoleMargin : Double;


begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then Exit;

    // --- Get values from TEdit components ---
    sWidth        := EditWidth.Text;
    sHeight       := EditHeight.Text;
    sFilletRadius := EditFilletRadius.Text;
    sHoleSize     := EditHoleSize.Text;
    sHoleMargin   := EditHoleMargin.Text;
    // Convert string values to Double
    dWidth := StrToFloatDef(sWidth, 0.0);
    if dWidth <= 0.0 then
    begin
        ShowMessage('Invalid or zero value for Width');
        Exit;
    end;

    dHeight := StrToFloatDef(sHeight, 0.0);
    if dHeight <= 0.0 then
    begin
        ShowMessage('Invalid or zero value for Height');
        Exit;
    end;

    dFilletRadius := StrToFloatDef(sFilletRadius, 0.0);
    if dFilletRadius < 0.0 then
    begin
        ShowMessage('Fillet Radius cannot be negative');
        Exit;
    end;

    dHoleSize := StrToFloatDef(sHoleSize, 0.0);
    if dHoleSize <= 0.0 then
    begin
        ShowMessage('Invalid or zero value for Hole Size');
        Exit;
    end;

    dHoleMargin := StrToFloatDef(sHoleMargin, 0.0);
    if dHoleMargin <= 0.0 then
    begin
        ShowMessage('Invalid or zero value for Hole Margin');
        Exit;
    end;

    // Define the layer for the board outline primitives
    L := eKeepOutLayer;

    // Convert input dimensions (in mm) to TCoord
    BoardWidth   := MMsToCoord(dWidth);
    BoardHeight  := MMsToCoord(dHeight);
    FilletRadius := MMsToCoord(dFilletRadius);
    HoleSize     := MMsToCoord(dHoleSize);
    HoleMargin   := MMsToCoord(dHoleMargin);

    // Calculate the center of the board
    CenterX := MMsToCoord(dWidth/2 + 50);
    CenterY := MMsToCoord(dHeight/2 + 50);

    // Line width for the board outline primitives
    LineWidth := MMsToCoord(0.2);

    PCBServer.PreProcess;
    try
        // Clear existing primitives on the outline layer
        Iterator := Board.BoardIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(eArcObject, eTrackObject));
        Iterator.AddFilter_LayerSet(MkSet(L));
        Iterator.AddFilter_Method(eProcessAll);

        Obj := Iterator.FirstPCBObject;
        while Obj <> nil do
        begin
            Board.RemovePCBObject(Obj);
            Obj := Iterator.NextPCBObject;
        end;
        Board.BoardIterator_Destroy(Iterator);

        // --- Create board outline ---
        if dFilletRadius > 0 then
        begin
            // Create rounded rectangle outline with arcs
            // Top-left arc
            Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
            Arc.Layer := L;
            Arc.LineWidth := LineWidth;
            Arc.Radius := FilletRadius;
            Arc.XCenter := CenterX - BoardWidth/2 + FilletRadius;
            Arc.YCenter := CenterY - BoardHeight/2 + FilletRadius;
            Arc.StartAngle := 180;
            Arc.EndAngle := 270;
            Board.AddPCBObject(Arc);

            // Top-right arc
            Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
            Arc.Layer := L;
            Arc.LineWidth := LineWidth;
            Arc.Radius := FilletRadius;
            Arc.XCenter := CenterX + BoardWidth/2 - FilletRadius;
            Arc.YCenter := CenterY - BoardHeight/2 + FilletRadius;
            Arc.StartAngle := 270;
            Arc.EndAngle := 0;
            Board.AddPCBObject(Arc);

            // Bottom-right arc
            Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
            Arc.Layer := L;
            Arc.LineWidth := LineWidth;
            Arc.Radius := FilletRadius;
            Arc.XCenter := CenterX + BoardWidth/2 - FilletRadius;
            Arc.YCenter := CenterY + BoardHeight/2 - FilletRadius;
            Arc.StartAngle := 0;
            Arc.EndAngle := 90;
            Board.AddPCBObject(Arc);

            // Bottom-left arc
            Arc := PCBServer.PCBObjectFactory(eArcObject, eNoDimension, eCreate_Default);
            Arc.Layer := L;
            Arc.LineWidth := LineWidth;
            Arc.Radius := FilletRadius;
            Arc.XCenter := CenterX - BoardWidth/2 + FilletRadius;
            Arc.YCenter := CenterY + BoardHeight/2 - FilletRadius;
            Arc.StartAngle := 90;
            Arc.EndAngle := 180;
            Board.AddPCBObject(Arc);

            // Top horizontal
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX - BoardWidth/2 + FilletRadius;
            Track.Y1 := CenterY - BoardHeight/2;
            Track.X2 := CenterX + BoardWidth/2 - FilletRadius;
            Track.Y2 := CenterY - BoardHeight/2;
            Board.AddPCBObject(Track);

            // Right vertical
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX + BoardWidth/2;
            Track.Y1 := CenterY - BoardHeight/2 + FilletRadius;
            Track.X2 := CenterX + BoardWidth/2;
            Track.Y2 := CenterY + BoardHeight/2 - FilletRadius;
            Board.AddPCBObject(Track);

            // Bottom horizontal (Fixed CageWidth to BoardWidth)
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX + BoardWidth/2 - FilletRadius;
            Track.Y1 := CenterY + BoardHeight/2;
            Track.X2 := CenterX - BoardWidth/2 + FilletRadius; // Corrected from CageWidth
            Track.Y2 := CenterY + BoardHeight/2;
            Board.AddPCBObject(Track);

            // Left vertical
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX - BoardWidth/2;
            Track.Y1 := CenterY + BoardHeight/2 - FilletRadius;
            Track.X2 := CenterX - BoardWidth/2;
            Track.Y2 := CenterY - BoardHeight/2 + FilletRadius;
            Board.AddPCBObject(Track);
        end
        else
        begin
            // Create sharp rectangle outline without arcs
            // Top horizontal
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX - BoardWidth/2;
            Track.Y1 := CenterY - BoardHeight/2;
            Track.X2 := CenterX + BoardWidth/2;
            Track.Y2 := CenterY - BoardHeight/2;
            Board.AddPCBObject(Track);

            // Right vertical
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX + BoardWidth/2;
            Track.Y1 := CenterY - BoardHeight/2;
            Track.X2 := CenterX + BoardWidth/2;
            Track.Y2 := CenterY + BoardHeight/2;
            Board.AddPCBObject(Track);

            // Bottom horizontal
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX + BoardWidth/2;
            Track.Y1 := CenterY + BoardHeight/2;
            Track.X2 := CenterX - BoardWidth/2;
            Track.Y2 := CenterY + BoardHeight/2;
            Board.AddPCBObject(Track);

            // Left vertical
            Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
            Track.Layer := L;
            Track.Width := LineWidth;
            Track.X1 := CenterX - BoardWidth/2;
            Track.Y1 := CenterY + BoardHeight/2;
            Track.X2 := CenterX - BoardWidth/2;
            Track.Y2 := CenterY - BoardHeight/2;
            Board.AddPCBObject(Track);
        end;
        RuleWidthChange(Board);
        // --- Create the four mounting holes ---
        PadSize := HoleSize * 1.65;

        MakeHole(Board, HoleSize, CenterX - BoardWidth/2 + HoleMargin, CenterY - BoardHeight/2 + HoleMargin);
        MakeHole(Board, HoleSize, CenterX + BoardWidth/2 - HoleMargin, CenterY - BoardHeight/2 + HoleMargin);
        MakeHole(Board, HoleSize, CenterX + BoardWidth/2 - HoleMargin, CenterY + BoardHeight/2 - HoleMargin);
        MakeHole(Board, HoleSize, CenterX - BoardWidth/2 + HoleMargin, CenterY + BoardHeight/2 - HoleMargin);

        // Select the newly created outline primitives
        Iterator := Board.BoardIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(eArcObject, eTrackObject));
        Iterator.AddFilter_LayerSet(MkSet(L));
        Iterator.AddFilter_Method(eProcessAll);

        Obj := Iterator.FirstPCBObject;
        while Obj <> nil do
        begin
            Obj.Selected := True;
            Obj := Iterator.NextPCBObject;
        end;
        Board.BoardIterator_Destroy(Iterator);

        // Redefine the board shape from selected primitives
        ResetParameters;
        AddStringParameter('MODE', 'BOARDOUTLINE_FROM_SEL_PRIMS');
        RunProcess('PCB:PlaceBoardOutline');

        // Deselect all primitives
        ResetParameters;
        AddStringParameter('Scope', 'All');
        RunProcess('PCB:DeSelect');

        // Delete the outline primitives from the outline layer
        Iterator := Board.BoardIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(eArcObject, eTrackObject));
        Iterator.AddFilter_LayerSet(MkSet(L));
        Iterator.AddFilter_Method(eProcessAll);

        Obj := Iterator.FirstPCBObject;
        while Obj <> nil do
        begin
            Board.RemovePCBObject(Obj);
            Obj := Iterator.NextPCBObject;
        end;
        Board.BoardIterator_Destroy(Iterator);

    finally
        PCBServer.PostProcess;
        Board.ViewManager_FullUpdate;
        Client.SendMessage('PCB:Zoom', 'Action=All', 255, Client.CurrentView);
        Close;
    end;
end;



procedure TPCBCreator.OnChange(Sender: TObject);
var
  Edit: TEdit;
  Text: WideString;
  i: Integer;
  Temp: WideString;
  DotCount: Integer;
begin
  // Cast Sender to TEdit (correct syntax for Altium)
  Edit := TEdit(Sender);
  Text := Edit.Text;

  if Length(Text) = 0 then
    Exit;

  Temp := '';
  DotCount := 0;

  // Loop through each character and filter out invalid ones
  for i := 1 to Length(Text) do
  begin
    case Text[i] of
      '0'..'9':
        Temp := Temp + Text[i];
      '.':
        begin
          if DotCount = 0 then
          begin
            Temp := Temp + Text[i];
            Inc(DotCount);
          end;
        end;
      '-', ',', #8: // Handle backspace or disallowed chars
        begin
          if Text[i] = #8 then
            Temp := Temp + Text[i]; // Allow backspace
          if Text[i] = ',' then
            Temp := Temp + '.'; // Optional: convert comma to dot
        end;
      else
        ; // Ignore other characters
    end;
  end;

  // If text has changed, update the edit box
  if Temp <> Text then
    Edit.Text := Temp;
end;

