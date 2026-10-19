object frameFIBPSViewer: TframeFIBPSViewer
  Left = 0
  Top = 0
  Width = 1024
  Height = 768
  TabOrder = 0
  PixelsPerInch = 96
  object pnlToolbar: TPanel
    Left = 0
    Top = 0
    Width = 1024
    Height = 36
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object btnProfile: TRzBitBtn
      Left = 4
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Profile'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 0
      OnClick = btnProfileClick
    end
    object btnDistance: TRzBitBtn
      Left = 82
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Distance'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 1
      OnClick = btnDistanceClick
    end
    object btnRoughness: TRzBitBtn
      Left = 160
      Top = 4
      Width = 80
      Height = 28
      Caption = 'Roughness'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 2
      OnClick = btnRoughnessClick
    end
    object btnFlatten: TRzBitBtn
      Left = 260
      Top = 4
      Width = 80
      Height = 28
      Caption = 'Flatten'
      AllowAllUp = True
      GroupIndex = 2
      TabOrder = 3
      OnClick = btnFlattenClick
    end
    object btnStepHeight: TRzBitBtn
      Left = 348
      Top = 4
      Width = 85
      Height = 28
      Caption = 'Step Height'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 4
      OnClick = btnStepHeightClick
    end
    object btnWearTrack: TRzBitBtn
      Left = 436
      Top = 4
      Width = 85
      Height = 28
      Caption = 'Wear Track'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 5
      OnClick = btnWearTrackClick
    end
    object btnCopyData: TRzBitBtn
      Left = 541
      Top = 4
      Width = 100
      Height = 28
      Caption = 'Copy Data'
      Enabled = False
      TabOrder = 6
      OnClick = btnCopyDataClick
    end
    object btnCopyImage: TRzBitBtn
      Left = 644
      Top = 4
      Width = 100
      Height = 28
      Caption = 'Copy Image'
      TabOrder = 7
      OnClick = btnCopyImageClick
    end
    object btnSave: TRzBitBtn
      Left = 747
      Top = 4
      Width = 100
      Height = 28
      Caption = 'Save'
      TabOrder = 8
      OnClick = btnSaveClick
    end
  end
  object Status: TRzStatusBar
    Left = 0
    Top = 749
    Width = 1024
    Height = 19
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderSides = [sdLeft, sdTop, sdRight, sdBottom]
    BorderWidth = 0
    Color = 15987699
    TabOrder = 1
  end
  object pnlInfo: TRzPanel
    Left = 0
    Top = 725
    Width = 1024
    Height = 24
    Align = alBottom
    Alignment = taLeftJustify
    BorderOuter = fsFlat
    Caption = ''
    TabOrder = 2
  end
  object ChartProfile: TChart
    Left = 0
    Top = 541
    Width = 1024
    Height = 180
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
    Title.Visible = False
    BottomAxis.LabelsFormat.Font.Height = -11
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.TickInnerLength = 4
    BottomAxis.TickLength = 0
    BottomAxis.Ticks.Width = 2
    BottomAxis.TicksInner.Width = 2
    BottomAxis.Title.Caption = 'Position (um)'
    BottomAxis.Title.Font.Height = -12
    LeftAxis.LabelsFormat.Font.Height = -11
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.TickInnerLength = 4
    LeftAxis.TickLength = 0
    LeftAxis.Ticks.Width = 2
    LeftAxis.TicksInner.Width = 2
    LeftAxis.Title.Caption = 'Height (um)'
    LeftAxis.Title.Font.Height = -12
    View3D = False
    Align = alBottom
    BevelOuter = bvLowered
    Color = clWhite
    TabOrder = 3
    Visible = False
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      5
      5
      5
      5)
    ColorPaletteIndex = 13
    object serProfileH: TFastLineSeries
      Title = 'Horizontal'
      LinePen.Color = clNavy
      LinePen.Width = 2
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serProfileV: TFastLineSeries
      Title = 'Vertical'
      LinePen.Color = clMaroon
      LinePen.Width = 2
      LinePen.Style = psDash
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serWearUpper: TFastLineSeries
      Title = 'Mean + SD'
      LinePen.Color = 8421631
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serWearLower: TFastLineSeries
      Title = 'Mean - SD'
      LinePen.Color = 8421631
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serWearMean: TFastLineSeries
      Title = 'Mean'
      LinePen.Color = clRed
      LinePen.Width = 2
      XValues.Name = 'X'
      XValues.Order = loNone
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
  end
  object SplitterProfile: TSplitter
    Left = 0
    Top = 538
    Width = 1024
    Height = 3
    Cursor = crVSplit
    Align = alBottom
    Visible = False
  end
  object pnlCenter: TPanel
    Left = 0
    Top = 36
    Width = 1024
    Height = 502
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 4
    object pbLegend: TPaintBox
      Left = 964
      Top = 0
      Width = 60
      Height = 502
      Align = alRight
      OnPaint = pbLegendPaint
    end
    object ScrollBox: TScrollBox
      Left = 0
      Top = 0
      Width = 964
      Height = 502
      Align = alClient
      TabOrder = 0
      OnMouseWheel = ScrollBoxMouseWheel
      OnResize = ScrollBoxResize
      object Image: TImage
        Left = 0
        Top = 0
        Width = 400
        Height = 400
        OnMouseDown = ImageMouseDown
        OnMouseMove = ImageMouseMove
        OnMouseUp = ImageMouseUp
        OnDblClick = ImageDblClick
      end
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = '.png'
    Filter = 'PNG Image|*.png|Text Data|*.txt|Wear Profile|*.txt'
    Left = 64
    Top = 80
  end
end
