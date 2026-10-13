object frameDepositionViewer: TframeDepositionViewer
  Left = 0
  Top = 0
  Width = 1482
  Height = 960
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  TabOrder = 0
  PixelsPerInch = 192
  object Pages: TRzTabControl
    Left = 0
    Top = 0
    Width = 1482
    Height = 960
    Hint = ''
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    ShowShadow = False
    TabOverlap = -2
    TabIndex = 0
    TabOrder = 0
    Tabs = <
      item
        Caption = 'Overview'
      end
      item
        Caption = 'Recipe'
      end
      item
        Caption = 'Pressure'
      end
      item
        Caption = 'Temperature'
      end
      item
        Caption = 'Gas Flow'
      end
      item
        Caption = 'Bias'
      end
      item
        Caption = 'V / I'
      end
      item
        Caption = 'Stage'
      end>
    OnChange = PagesChange
    FixedDimension = 38
    object Cards: TCardPanel
      Left = 1
      Top = 39
      Width = 1478
      Height = 918
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Align = alClient
      BevelOuter = bvNone
      ActiveCard = CardOverview
      Caption = 'Cards'
      TabOrder = 0
      object CardOverview: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardOverview'
        BevelOuter = bvNone
        CardIndex = 0
        TabOrder = 0
        object lvOverview: TListView
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alClient
          Columns = <
            item
              Caption = 'Property'
              Width = 400
            end
            item
              Caption = 'Value'
              Width = 1000
            end>
          GroupView = True
          ReadOnly = True
          RowSelect = True
          ParentShowHint = False
          ShowHint = True
          TabOrder = 0
          ViewStyle = vsReport
          OnCustomDrawSubItem = lvOverviewCustomDrawSubItem
          OnDblClick = lvOverviewDblClick
          OnInfoTip = lvOverviewInfoTip
          OnMouseMove = lvOverviewMouseMove
        end
      end
      object CardRecipe: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardRecipe'
        BevelOuter = bvNone
        CardIndex = 1
        TabOrder = 1
        object lvRecipeParams: TListView
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 320
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alTop
          Columns = <
            item
              Caption = 'Group'
              Width = 240
            end
            item
              Caption = 'Parameter'
              Width = 300
            end
            item
              Caption = 'Value'
              Width = 240
            end
            item
              Caption = 'Unit'
              Width = 160
            end>
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
        end
        object synScript: TSynEdit
          AlignWithMargins = True
          Left = 6
          Top = 338
          Width = 1464
          Height = 572
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alClient
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -24
          Font.Name = 'Consolas'
          Font.Style = []
          Font.Quality = fqClearTypeNatural
          TabOrder = 1
          CodeFolding.ShowCollapsedLine = True
          UseCodeFolding = False
          BorderStyle = bsNone
          ExtraLineSpacing = 4
          Gutter.DigitCount = 2
          Gutter.Font.Charset = DEFAULT_CHARSET
          Gutter.Font.Color = clWindowText
          Gutter.Font.Height = -20
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
          Highlighter = Syn
          ReadOnly = True
          SelectedColor.Alpha = 0.400000005960464500
        end
      end
      object CardPressure: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardPressure'
        BevelOuter = bvNone
        CardIndex = 2
        TabOrder = 2
        object ChartPressure: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Pressure')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.Logarithmic = True
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardTemperature: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardTemperature'
        BevelOuter = bvNone
        CardIndex = 3
        TabOrder = 3
        object ChartTemperature: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Temperature')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardGas: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardGas'
        BevelOuter = bvNone
        CardIndex = 4
        TabOrder = 4
        object ChartGas: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Gas Flow')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardBias: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardBias'
        BevelOuter = bvNone
        CardIndex = 5
        TabOrder = 5
        object ChartBias: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Bias')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardVI: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardVI'
        BevelOuter = bvNone
        CardIndex = 6
        TabOrder = 6
        object ChartVI: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Voltage / Current')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardStage: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardStage'
        BevelOuter = bvNone
        CardIndex = 7
        TabOrder = 7
        object ChartStage: TChart
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Cursor = crCross
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Gradient.Colors = <
            item
              Color = 16772033
            end
            item
              Color = clWhite
              Offset = 0.562874251497006000
            end
            item
              Color = clWhite
              Offset = 1.000000000000000000
            end>
          Gradient.EndColor = clWhite
          Gradient.MidColor = clWhite
          Gradient.StartColor = 16772033
          Legend.CheckBoxes = True
          Legend.Font.Height = -16
          Legend.ResizeChart = False
          Legend.Shadow.HorizSize = 6
          Legend.Shadow.VertSize = 6
          Legend.TextSymbolGap = 7
          Legend.TopPos = 8
          MarginBottom = 2
          MarginLeft = 1
          MarginRight = 1
          MarginTop = 1
          Title.Font.Color = 8404992
          Title.Font.Height = -13
          Title.Font.Style = [fsBold]
          Title.Text.Strings = (
            'Stage')
          BottomAxis.Title.Caption = 'Elapsed [s]'
          BottomAxis.Title.Font.Height = -13
          BottomAxis.Title.Font.Style = [fsBold]
          LeftAxis.LabelsFormat.Font.Height = -13
          Shadow.Visible = False
          View3D = False
          View3DOptions.FontZoom = 200
          View3DOptions.PenZoom = 200
          View3DOptions.CheckBoxZoom = 200
          View3DOptions.Orthogonal = False
          Align = alClient
          BevelOuter = bvNone
          Color = 16579836
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
        end
      end
      object CardText: TCard
        Left = 1
        Top = 1
        Width = 1476
        Height = 916
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Margins.Bottom = 6
        Caption = 'CardText'
        BevelOuter = bvNone
        CardIndex = 8
        TabOrder = 8
        object memText: TMemo
          AlignWithMargins = True
          Left = 6
          Top = 6
          Width = 1464
          Height = 904
          Margins.Left = 6
          Margins.Top = 6
          Margins.Right = 6
          Margins.Bottom = 6
          Align = alClient
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -24
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          ReadOnly = True
          ScrollBars = ssBoth
          TabOrder = 0
          WordWrap = False
        end
      end
    end
  end
  object Syn: TSynGeneralSyn
    CommentAttri.Foreground = clGreen
    Comments = [csCPPStyle]
    DetectPreprocessor = True
    IdentifierAttri.Foreground = clBlue
    IdentifierChars = '$_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    KeyWords.Strings = (
      'ABORT'
      'BEGIN'
      'BIAS'
      'BIASARB'
      'CALL'
      'CHECK'
      'DELAY'
      'DEPOSIT'
      'ELSE'
      'END'
      'ENDFUNCTION'
      'ENDIF'
      'ENDLOOP'
      'FINISH'
      'FUNCTION'
      'GOTO'
      'HOLDER'
      'HOME'
      'IF'
      'LABEL'
      'LOOP'
      'MESSAGE'
      'MFC'
      'POWER'
      'PRESSURE'
      'PUMP'
      'PWAIT'
      'RAMP'
      'ROTATE'
      'ROTATION'
      'SCAN'
      'SET'
      'SHUTTER'
      'STAGE'
      'START'
      'STATE'
      'SWAIT'
      'TRANSFER'
      'VALVE'
      'VAR'
      'WAIT'
      'WARMUP')
    NumberAttri.Foreground = clMaroon
    PreprocessorAttri.Foreground = clGreen
    StringAttri.Foreground = clTeal
    StringAttri.Style = [fsItalic]
    SymbolAttri.Foreground = clNavy
    SymbolAttri.Style = [fsItalic]
    StringDelim = sdDoubleQuote
    Left = 100
    Top = 100
  end
end
