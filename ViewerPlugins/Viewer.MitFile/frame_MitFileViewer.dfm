object frameMitFileViewer: TframeMitFileViewer
  Left = 0
  Top = 0
  Width = 888
  Height = 621
  TabOrder = 0
  PixelsPerInch = 96
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 200
    Height = 602
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 0
    object lblRecords: TLabel
      Left = 8
      Top = 4
      Width = 42
      Height = 13
      Caption = 'Records:'
    end
    object lblInfo: TLabel
      Left = 8
      Top = 372
      Width = 180
      Height = 226
      Anchors = [akLeft, akRight, akBottom]
      AutoSize = False
      Caption = ' '
      WordWrap = True
    end
    object lstRecords: TCheckListBox
      Left = 0
      Top = 20
      Width = 200
      Height = 306
      Anchors = [akLeft, akTop, akRight, akBottom]
      ItemHeight = 13
      TabOrder = 0
      OnClick = lstRecordsClick
      OnClickCheck = lstRecordsClickCheck
    end
    object pnlToolbar: TPanel
      Left = 0
      Top = 326
      Width = 200
      Height = 40
      Anchors = [akLeft, akRight, akBottom]
      BevelOuter = bvNone
      TabOrder = 1
      object btnSelectAll: TRzBitBtn
        Left = 4
        Top = 8
        Width = 55
        Height = 25
        Caption = 'All'
        TabOrder = 0
        OnClick = btnSelectAllClick
      end
      object btnSelectNone: TRzBitBtn
        Left = 62
        Top = 8
        Width = 55
        Height = 25
        Caption = 'None'
        TabOrder = 1
        OnClick = btnSelectNoneClick
      end
      object btnAverage: TRzBitBtn
        Left = 120
        Top = 8
        Width = 72
        Height = 25
        Caption = 'Average'
        AllowAllUp = True
        GroupIndex = 1
        TabOrder = 2
        OnClick = btnAverageClick
      end
    end
  end
  object Status: TRzStatusBar
    Left = 0
    Top = 602
    Width = 888
    Height = 19
    Align = alBottom
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderSides = [sdLeft, sdTop, sdRight, sdBottom]
    BorderWidth = 0
    Color = 15987699
    TabOrder = 1
    object spStatus: TRzStatusPane
      Left = 0
      Top = 0
      Width = 888
      Height = 19
      Align = alClient
      AutoSize = True
    end
  end
  object Chart: TChart
    AlignWithMargins = True
    Left = 203
    Top = 3
    Width = 682
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
      'Nanoindentation')
    Title.Visible = False
    BottomAxis.LabelsFormat.Font.Height = -11
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.TickInnerLength = 4
    BottomAxis.TickLength = 0
    BottomAxis.Ticks.Width = 2
    BottomAxis.TicksInner.Width = 2
    BottomAxis.Title.Caption = 'Pd (nm)'
    BottomAxis.Title.Font.Height = -13
    LeftAxis.LabelsFormat.Font.Height = -11
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.TickInnerLength = 4
    LeftAxis.TickLength = 0
    LeftAxis.Ticks.Width = 2
    LeftAxis.TicksInner.Width = 2
    LeftAxis.Title.Caption = 'Fn (mN)'
    LeftAxis.Title.Font.Height = -13
    RightAxis.Labels = False
    RightAxis.LabelsFormat.Visible = False
    TopAxis.Labels = False
    TopAxis.LabelsFormat.Visible = False
    View3D = False
    AllowPanning = pmBoth
    Zoom.Pen.Color = clRed
    Zoom.Pen.Mode = pmNotXor
    Align = alClient
    BevelOuter = bvLowered
    Color = clCream
    TabOrder = 2
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      5
      5
      5
      5)
    ColorPaletteIndex = 13
    object btnCopy: TRzBitBtn
      Left = 552
      Top = 8
      Width = 121
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Copy to clipboard'
      TabOrder = 0
      OnClick = btnCopyClick
    end
    object btnSave: TRzBitBtn
      Left = 552
      Top = 39
      Width = 121
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Save to File'
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object serLoading: TFastLineSeries
      Title = 'Indent'
      LinePen.Color = clBlue
      LinePen.Width = 1
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serUnloading: TFastLineSeries
      Title = 'Unloading'
      LinePen.Color = clBlue
      LinePen.Width = 1
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serDrift: TFastLineSeries
      Title = 'Drift'
      LinePen.Color = clGray
      LinePen.Width = 1
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = '.dat'
    Filter = 'DAT (ASCII)|*.dat|TXT|*.txt'
    Left = 128
    Top = 150
  end
end
