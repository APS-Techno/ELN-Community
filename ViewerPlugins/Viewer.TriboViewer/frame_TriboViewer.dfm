object frameTriboViewer: TframeTriboViewer
  Left = 0
  Top = 0
  Width = 888
  Height = 621
  TabOrder = 0
  PixelsPerInch = 96
  object Status: TRzStatusBar
    Left = 0
    Top = 602
    Width = 888
    Height = 19
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderSides = [sdLeft, sdTop, sdRight, sdBottom]
    BorderWidth = 0
    Color = 15987699
    TabOrder = 0
  end
  object Chart: TChart
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 882
    Height = 596
    Cursor = crCross
    Foot.Visible = False
    Legend.Visible = False
    MarginBottom = 2
    MarginLeft = 6
    MarginRight = 2
    MarginTop = 2
    MarginUnits = muPixels
    PrintProportional = False
    SubFoot.Visible = False
    SubTitle.Visible = False
    Title.Text.Strings = (
      'TriboViewer')
    Title.Visible = False
    BottomAxis.LabelsFormat.Font.Height = -11
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.TickInnerLength = 4
    BottomAxis.TickLength = 0
    BottomAxis.Ticks.Width = 2
    BottomAxis.TicksInner.Width = 2
    BottomAxis.Title.Caption = 'X'
    BottomAxis.Title.Font.Height = -13
    LeftAxis.LabelsFormat.Font.Height = -11
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.TickInnerLength = 4
    LeftAxis.TickLength = 0
    LeftAxis.Ticks.Width = 2
    LeftAxis.TicksInner.Width = 2
    LeftAxis.Title.Caption = 'Y'
    LeftAxis.Title.Font.Height = -13
    RightAxis.Labels = False
    RightAxis.LabelsFormat.Visible = False
    TopAxis.Labels = False
    TopAxis.LabelsFormat.Visible = False
    View3D = False
    Zoom.Pen.Color = clRed
    Zoom.Pen.Mode = pmNotXor
    Align = alClient
    BevelOuter = bvLowered
    Color = clCream
    TabOrder = 1
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      5
      5
      5
      5)
    ColorPaletteIndex = 13
    object btnCopy: TRzBitBtn
      Left = 752
      Top = 8
      Width = 121
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Copy to clipboard'
      TabOrder = 0
      OnClick = btnCopyClick
    end
    object btnSave: TRzBitBtn
      Left = 752
      Top = 39
      Width = 121
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Save to File'
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object Series1: TFastLineSeries
      LinePen.Color = clNavy
      LinePen.Width = 2
      XValues.Name = 'X'
      XValues.Order = loAscending
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = '.dat'
    Filter = 'DAT (ASCII)|*.dat|TXT|*.txt'
    Left = 200
    Top = 150
  end
end
