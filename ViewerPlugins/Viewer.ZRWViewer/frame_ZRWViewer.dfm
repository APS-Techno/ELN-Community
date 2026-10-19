object frameZRWViewer: TframeZRWViewer
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
  object pnlSelection: TPanel
    Left = 0
    Top = 0
    Width = 888
    Height = 84
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 2
    DesignSize = (
      888
      84)
    object lblMode: TLabel
      Left = 8
      Top = 12
      Width = 44
      Height = 15
      Caption = 'Interval:'
    end
    object lblStart: TLabel
      Left = 258
      Top = 12
      Width = 28
      Height = 15
      Caption = 'From'
    end
    object lblEnd: TLabel
      Left = 384
      Top = 12
      Width = 14
      Height = 15
      Caption = 'To'
    end
    object lblStats: TLabel
      Left = 8
      Top = 42
      Width = 872
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Caption = 'lblStats'
    end
    object lblWarnings: TLabel
      Left = 8
      Top = 61
      Width = 872
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clMaroon
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object btnAutomatic: TSpeedButton
      Left = 62
      Top = 7
      Width = 90
      Height = 25
      GroupIndex = 1
      Down = True
      Caption = 'Automatic'
      OnClick = ModeButtonClick
    end
    object btnManual: TSpeedButton
      Left = 152
      Top = 7
      Width = 90
      Height = 25
      GroupIndex = 1
      Caption = 'Manual'
      OnClick = ModeButtonClick
    end
    object edStart: TEdit
      Left = 292
      Top = 8
      Width = 84
      Height = 23
      TabOrder = 1
      OnChange = edBoundChange
    end
    object edEnd: TEdit
      Left = 404
      Top = 8
      Width = 84
      Height = 23
      TabOrder = 2
      OnChange = edBoundChange
    end
    object chkThroughEnd: TCheckBox
      Left = 500
      Top = 10
      Width = 108
      Height = 19
      Caption = 'Through end'
      TabOrder = 3
      OnClick = chkThroughEndClick
    end
    object btnApply: TButton
      Left = 620
      Top = 7
      Width = 80
      Height = 25
      Caption = 'Apply'
      TabOrder = 4
      OnClick = btnApplyClick
    end
    object btnReload: TButton
      Left = 708
      Top = 7
      Width = 80
      Height = 25
      Caption = 'Reload'
      TabOrder = 5
      OnClick = btnReloadClick
    end
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
      'ZRW Viewer')
    Title.Visible = False
    BottomAxis.LabelsFormat.Font.Height = -11
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.TickInnerLength = 4
    BottomAxis.TickLength = 0
    BottomAxis.Ticks.Width = 2
    BottomAxis.TicksInner.Width = 2
    BottomAxis.Title.Caption = 'Cycles'
    BottomAxis.Title.Font.Height = -13
    LeftAxis.LabelsFormat.Font.Height = -11
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.TickInnerLength = 4
    LeftAxis.TickLength = 0
    LeftAxis.Ticks.Width = 2
    LeftAxis.TicksInner.Width = 2
    LeftAxis.Title.Caption = 'COF'
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
    object SeriesBand: TAreaSeries
      Marks.Visible = False
      ShowInLegend = False
      AreaColor = 16764057
      AreaLinesPen.Visible = False
      Transparency = 65
      XValues.Name = 'X'
      XValues.Order = loAscending
      YValues.Name = 'Y'
      YValues.Order = loNone
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
