object frameVK4Viewer: TframeVK4Viewer
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
    object lblChannel: TLabel
      Left = 8
      Top = 10
      Width = 46
      Height = 13
      Caption = 'Channel:'
    end
    object cboChannel: TComboBox
      Left = 60
      Top = 6
      Width = 140
      Height = 21
      Style = csDropDownList
      TabOrder = 0
      OnChange = cboChannelChange
    end
    object btnProfile: TRzBitBtn
      Left = 214
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Profile'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 1
      OnClick = btnProfileClick
    end
    object btnDistance: TRzBitBtn
      Left = 292
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Distance'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 2
      OnClick = btnDistanceClick
    end
    object btnRoughness: TRzBitBtn
      Left = 370
      Top = 4
      Width = 80
      Height = 28
      Caption = 'Roughness'
      AllowAllUp = True
      GroupIndex = 1
      TabOrder = 3
      OnClick = btnRoughnessClick
    end
    object btnFlatten: TRzBitBtn
      Left = 470
      Top = 4
      Width = 80
      Height = 28
      Caption = 'Flatten'
      AllowAllUp = True
      GroupIndex = 2
      TabOrder = 4
      OnClick = btnFlattenClick
    end
    object btnCopy: TRzBitBtn
      Left = 570
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Copy'
      TabOrder = 5
      OnClick = btnCopyClick
    end
    object btnSave: TRzBitBtn
      Left = 648
      Top = 4
      Width = 75
      Height = 28
      Caption = 'Save'
      TabOrder = 6
      OnClick = btnSaveClick
    end
    object btnFitPage: TRzBitBtn
      Left = 740
      Top = 4
      Width = 60
      Height = 28
      Caption = 'Fit'
      TabOrder = 7
      OnClick = btnFitPageClick
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
    Top = 730
    Width = 1024
    Height = 19
    Align = alBottom
    Alignment = taLeftJustify
    BorderOuter = fsNone
    TabOrder = 2
  end
  object SplitterProfile: TSplitter
    Left = 0
    Top = 550
    Width = 1024
    Height = 4
    Cursor = crVSplit
    Align = alBottom
    Visible = False
    ExplicitTop = 530
  end
  object ChartProfile: TChart
    Left = 0
    Top = 554
    Width = 1024
    Height = 176
    AllowPanning = pmHorizontal
    Legend.Visible = False
    Title.Visible = False
    BottomAxis.Title.Caption = #181'm'
    LeftAxis.Title.Caption = #181'm'
    View3D = False
    Align = alBottom
    TabOrder = 3
    Visible = False
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      15
      22
      15
      22)
    ColorPaletteIndex = 13
    object serProfileH: TFastLineSeries
      LinePen.Color = clRed
      XValues.Name = 'X'
      XValues.Order = loAscending
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
    object serProfileV: TFastLineSeries
      LinePen.Color = clBlue
      XValues.Name = 'X'
      XValues.Order = loAscending
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
  end
  object pnlCenter: TPanel
    Left = 0
    Top = 36
    Width = 1024
    Height = 514
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 4
    object pbLegend: TPaintBox
      Left = 984
      Top = 0
      Width = 40
      Height = 514
      Align = alRight
      OnPaint = pbLegendPaint
    end
    object ScrollBox: TScrollBox
      Left = 0
      Top = 0
      Width = 984
      Height = 514
      Align = alClient
      BorderStyle = bsNone
      TabOrder = 0
      OnMouseWheel = ScrollBoxMouseWheel
      OnResize = ScrollBoxResize
      object Image: TImage
        Left = 0
        Top = 0
        Width = 512
        Height = 512
        OnDblClick = ImageDblClick
        OnMouseDown = ImageMouseDown
        OnMouseMove = ImageMouseMove
        OnMouseUp = ImageMouseUp
      end
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'png'
    Filter = 'PNG Image (*.png)|*.png|Tab-separated text (*.txt)|*.txt'
    Title = 'Save VK4 Data'
    Left = 960
    Top = 4
  end
end
