object frameLAMMPSViewer: TframeLAMMPSViewer
  Left = 0
  Top = 0
  Width = 888
  Height = 621
  TabOrder = 0
  PixelsPerInch = 96
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 882
    Height = 40
    Align = alTop
    BevelWidth = 2
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblTitle: TRzLabel
      Left = 12
      Top = 10
      Width = 40
      Height = 18
      Caption = 'lblTitle'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -15
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object Pages: TPageControl
    AlignWithMargins = True
    Left = 3
    Top = 49
    Width = 882
    Height = 550
    ActivePage = tabLmpin
    Align = alClient
    Style = tsFlatButtons
    TabOrder = 1
    object tabLmpin: TTabSheet
      Caption = 'Input Script'
      TabVisible = False
      object Editor: TSynEdit
        Left = 0
        Top = 0
        Width = 874
        Height = 519
        Align = alClient
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -15
        Font.Name = 'Consolas'
        Font.Style = []
        Font.Quality = fqClearTypeNatural
        TabOrder = 0
        CodeFolding.ShowCollapsedLine = True
        UseCodeFolding = False
        BookMarkOptions.LeftMargin = 4
        BookMarkOptions.Xoffset = 12
        ExtraLineSpacing = 2
        Gutter.DigitCount = 3
        Gutter.Font.Charset = DEFAULT_CHARSET
        Gutter.Font.Color = clWindowText
        Gutter.Font.Height = -13
        Gutter.Font.Name = 'Consolas'
        Gutter.Font.Style = []
        Gutter.Font.Quality = fqClearTypeNatural
        Gutter.ShowLineNumbers = True
        Gutter.Bands = <
          item
            Kind = gbkMarks
            Width = 13
          end
          item
            Kind = gbkLineNumbers
          end
          item
            Kind = gbkFold
          end
          item
            Kind = gbkTrackChanges
          end
          item
            Kind = gbkMargin
            Width = 3
          end>
        ReadOnly = True
        SelectedColor.Alpha = 0.400000005960464500
      end
    end
    object tabDump: TTabSheet
      Caption = 'Data File'
      ImageIndex = 1
      TabVisible = False
      object pnlInfo: TPanel
        Left = 0
        Top = 0
        Width = 220
        Height = 519
        Align = alLeft
        BevelOuter = bvNone
        TabOrder = 0
        object lblInfo: TLabel
          Left = 8
          Top = 8
          Width = 204
          Height = 423
          Anchors = [akLeft, akTop, akRight, akBottom]
          AutoSize = False
          Caption = ' '
          WordWrap = True
        end
        object pnlCrossSection: TPanel
          Left = 0
          Top = 439
          Width = 220
          Height = 80
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 1
          object lblSlab: TLabel
            Left = 8
            Top = 28
            Width = 60
            Height = 15
            Caption = 'Slab: 10%'
          end
          object chkCrossSection: TCheckBox
            Left = 8
            Top = 6
            Width = 200
            Height = 17
            Caption = 'Cross-section (XZ mid-plane)'
            TabOrder = 0
          end
          object trkSlab: TTrackBar
            Left = 0
            Top = 48
            Width = 220
            Height = 28
            Max = 50
            Min = 1
            Position = 10
            ShowSelRange = False
            TabOrder = 1
            TickStyle = tsNone
          end
        end
      end
      object Chart: TChart
        AlignWithMargins = True
        Left = 223
        Top = 3
        Width = 651
        Height = 513
        Cursor = crCross
        Foot.Visible = False
        Legend.Visible = True
        Legend.Alignment = laTop
        MarginBottom = 2
        MarginLeft = 6
        MarginRight = 8
        MarginTop = 2
        MarginUnits = muPixels
        PrintProportional = False
        SubFoot.Visible = False
        SubTitle.Visible = False
        Title.Text.Strings = (
          'Atom Positions (XY)')
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
        LeftAxis.Title.Caption = 'Z'
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
        Color = clDkGray
        TabOrder = 1
        DefaultCanvas = 'TGDIPlusCanvas'
        PrintMargins = (
          5
          5
          5
          5)
        ColorPaletteIndex = 13
      end
    end
  end
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
    TabOrder = 2
  end
end
