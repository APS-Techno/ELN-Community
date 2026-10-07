object frameColumnarDataViewer: TframeColumnarDataViewer
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
  object Pages: TRzTabControl
    Left = 0
    Top = 0
    Width = 888
    Height = 602
    Hint = ''
    Align = alClient
    ShowShadow = False
    TabOverlap = -2
    TabIndex = 0
    TabOrder = 1
    Tabs = <
      item
        Caption = 'Chart'
      end
      item
        Caption = 'Text'
      end>
    OnChange = PagesChange
    object Cards: TCardPanel
      Left = 1
      Top = 20
      Width = 886
      Height = 581
      Align = alClient
      BevelOuter = bvNone
      ActiveCard = CardChart
      Caption = 'Cards'
      TabOrder = 0
      object CardChart: TCard
        Left = 1
        Top = 1
        Width = 884
        Height = 579
        Caption = 'CardChart'
        BevelOuter = bvNone
        CardIndex = 0
        TabOrder = 0
        object Chart: TChart
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 878
          Height = 573
          Cursor = crCross
          Foot.Visible = False
          Legend.Visible = True
          Legend.Alignment = laTop
          Legend.LegendStyle = lsSeries
          Legend.Shadow.Visible = False
          Legend.Symbol.Width = 20
          Legend.TopPos = 0
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
          BottomAxis.Title.Font.Height = -13
          LeftAxis.LabelsFormat.Font.Height = -11
          LeftAxis.MinorTicks.Visible = False
          LeftAxis.TickInnerLength = 4
          LeftAxis.TickLength = 0
          LeftAxis.Ticks.Width = 2
          LeftAxis.TicksInner.Width = 2
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
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          PrintMargins = (
            5
            5
            5
            5)
          ColorPaletteIndex = 13
          object btnCopy: TRzBitBtn
            Left = 748
            Top = 8
            Width = 121
            Height = 25
            Anchors = [akTop, akRight]
            Caption = 'Copy to clipboard'
            TabOrder = 0
            OnClick = btnCopyClick
          end
          object btnSave: TRzBitBtn
            Left = 748
            Top = 39
            Width = 121
            Height = 25
            Anchors = [akTop, akRight]
            Caption = 'Save to File'
            TabOrder = 1
            OnClick = btnSaveClick
          end
        end
      end
      object CardText: TCard
        Left = 1
        Top = 1
        Width = 884
        Height = 579
        Caption = 'CardText'
        BevelOuter = bvNone
        CardIndex = 1
        TabOrder = 1
        object pnlTextTools: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 878
          Height = 35
          Align = alTop
          BevelWidth = 2
          BorderOuter = fsFlatRounded
          TabOrder = 0
          object btnCopyText: TRzBitBtn
            AlignWithMargins = True
            Left = 632
            Top = 4
            Width = 121
            Height = 25
            Anchors = [akTop, akRight]
            Caption = 'Copy to clipboard'
            TabOrder = 0
            OnClick = btnCopyClick
          end
          object btnSaveText: TRzBitBtn
            AlignWithMargins = True
            Left = 753
            Top = 4
            Width = 121
            Height = 25
            Anchors = [akTop, akRight]
            Caption = 'Save to File'
            TabOrder = 1
            OnClick = btnSaveClick
          end
        end
        object memText: TMemo
          AlignWithMargins = True
          Left = 3
          Top = 44
          Width = 878
          Height = 532
          Align = alClient
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          ReadOnly = True
          ScrollBars = ssBoth
          TabOrder = 1
          WordWrap = False
        end
      end
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = '.dat'
    Filter = 'DAT (ASCII)|*.dat|CSV|*.csv|TXT|*.txt'
    Left = 200
    Top = 150
  end
end
