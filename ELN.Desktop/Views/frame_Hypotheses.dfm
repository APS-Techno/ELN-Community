object frameHypotheses: TframeHypotheses
  Left = 0
  Top = 0
  Width = 900
  Height = 640
  Align = alClient
  TabOrder = 0
  object pnlToolbar: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 894
    Height = 38
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblProject: TLabel
      AlignWithMargins = True
      Left = 9
      Top = 4
      Width = 367
      Height = 30
      Margins.Left = 8
      Align = alClient
      AutoSize = False
      Caption = 'Hypotheses'
      EllipsisPosition = epEndEllipsis
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Layout = tlCenter
    end
    object pnlToolbarButtons: TPanel
      AlignWithMargins = True
      Left = 382
      Top = 4
      Width = 508
      Height = 30
      Margins.Top = 0
      Margins.Bottom = 0
      Align = alRight
      BevelOuter = bvNone
      ParentBackground = True
      TabOrder = 0
      object btnNewRoot: TButton
        Left = 0
        Top = 1
        Width = 120
        Height = 27
        Hint = 'Propose a new hypothesis in this project'
        Caption = 'New hypothesis...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 0
        OnClick = btnNewRootClick
      end
      object btnNewChild: TButton
        Left = 124
        Top = 1
        Width = 120
        Height = 27
        Hint =
          'Propose a follow-up that builds on the selected hypothesis and s' +
          'ays what changes'
        Caption = 'New follow-up...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
        OnClick = btnNewChildClick
      end
      object btnEdit: TButton
        Left = 248
        Top = 1
        Width = 80
        Height = 27
        Hint = 'Change the proposal while it still waits for approval'
        Caption = 'Edit...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 2
        OnClick = btnEditClick
      end
      object btnAbandon: TButton
        Left = 332
        Top = 1
        Width = 90
        Height = 27
        Hint = 'Stop work on this hypothesis. It stays in the list as Abandoned.'
        Caption = 'Abandon...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 3
        OnClick = btnAbandonClick
      end
      object btnRefresh: TButton
        Left = 426
        Top = 1
        Width = 80
        Height = 27
        Hint = 'Load the latest changes, including those made by others'
        Caption = 'Refresh'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 4
        OnClick = btnRefreshClick
      end
    end
  end
  object splMain: TSplitter
    Left = 426
    Top = 44
    Width = 5
    Height = 596
  end
  object vstHypotheses: TVirtualStringTree
    AlignWithMargins = True
    Left = 3
    Top = 47
    Width = 420
    Height = 590
    Align = alLeft
    DefaultNodeHeight = 26
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    Header.AutoSizeIndex = 0
    Header.Font.Charset = DEFAULT_CHARSET
    Header.Font.Color = clWindowText
    Header.Font.Height = -12
    Header.Font.Name = 'Segoe UI'
    Header.Font.Style = []
    Header.Height = 21
    Header.Options = [hoAutoResize, hoColumnResize, hoVisible]
    Header.ParentFont = False
    ParentFont = False
    TabOrder = 1
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnAfterCellPaint = vstHypothesesAfterCellPaint
    OnBeforeCellPaint = vstHypothesesBeforeCellPaint
    OnFocusChanged = vstHypothesesFocusChanged
    OnGetCellText = vstHypothesesGetCellText
    OnGetNodeDataSize = vstHypothesesGetNodeDataSize
    OnPaintText = vstHypothesesPaintText
    Columns = <
      item
        Position = 0
        Text = 'Hypothesis'
        Width = 150
      end
      item
        Position = 1
        Text = 'Status'
        Width = 130
      end
      item
        Position = 2
        Text = 'Key value'
        Width = 136
      end>
  end
  object lblEmpty: TLabel
    AlignWithMargins = True
    Left = 434
    Top = 47
    Width = 463
    Height = 590
    Align = alClient
    Alignment = taCenter
    Caption = 'Select a hypothesis on the left.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -13
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    Layout = tlCenter
    WordWrap = True
    Visible = False
  end
  object pnlDetail: TRzPanel
    AlignWithMargins = True
    Left = 434
    Top = 47
    Width = 463
    Height = 590
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object lblTitle: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 453
      Height = 20
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -15
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      WordWrap = True
    end
    object lblStatus: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 31
      Width = 453
      Height = 15
      Align = alTop
      WordWrap = True
    end
    object lblWarning: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 52
      Width = 453
      Height = 15
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clRed
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      StyleElements = [seClient, seBorder]
      WordWrap = True
      Visible = False
    end
    object lblNotice: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 73
      Width = 453
      Height = 15
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 32976
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      StyleElements = [seClient, seBorder]
      WordWrap = True
      Visible = False
    end
    object pcDetail: TPageControl
      AlignWithMargins = True
      Left = 5
      Top = 94
      Width = 453
      Height = 285
      ActivePage = tsOverview
      Align = alClient
      TabOrder = 0
      object tsOverview: TTabSheet
        Caption = 'Proposal'
        object lblKeyValue: TLabel
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 439
          Height = 15
          Align = alTop
          WordWrap = True
          Visible = False
        end
        object lblStatementCap: TLabel
          AlignWithMargins = True
          Left = 3
          Top = 24
          Width = 439
          Height = 15
          Align = alTop
          Caption = 'We expected'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Segoe UI'
          Font.Style = [fsBold]
          ParentFont = False
        end
        object memStatement: TMemo
          AlignWithMargins = True
          Left = 3
          Top = 45
          Width = 439
          Height = 76
          Align = alClient
          ReadOnly = True
          ScrollBars = ssVertical
          TabOrder = 0
        end
        object pnlChange: TPanel
          AlignWithMargins = True
          Left = 3
          Top = 127
          Width = 439
          Height = 125
          Align = alBottom
          BevelOuter = bvNone
          TabOrder = 1
          object lblChangeCap: TLabel
            AlignWithMargins = True
            Left = 0
            Top = 3
            Width = 439
            Height = 15
            Margins.Left = 0
            Margins.Right = 0
            Align = alTop
            Caption = 'What changes'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clWindowText
            Font.Height = -12
            Font.Name = 'Segoe UI'
            Font.Style = [fsBold]
            ParentFont = False
          end
          object memChange: TMemo
            AlignWithMargins = True
            Left = 0
            Top = 24
            Width = 439
            Height = 98
            Margins.Left = 0
            Margins.Right = 0
            Align = alClient
            ReadOnly = True
            ScrollBars = ssVertical
            TabOrder = 0
          end
        end
      end
      object tsRuns: TTabSheet
        Caption = 'Runs'
        ImageIndex = 1
        object lvRuns: TListView
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 439
          Height = 203
          Align = alClient
          Columns = <
            item
              Caption = 'Item'
              Width = 220
            end
            item
              Caption = 'Attached as'
              Width = 100
            end
            item
              Caption = 'Warning'
              Width = 80
            end>
          HideSelection = False
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
          OnCustomDrawItem = lvRunsCustomDrawItem
          OnDblClick = lvRunsDblClick
        end
        object pnlRunButtons: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 212
          Width = 439
          Height = 40
          Align = alBottom
          BorderOuter = fsFlatRounded
          TabOrder = 1
          object lblRunsHint: TLabel
            Left = 290
            Top = 12
            Width = 146
            Height = 15
            Caption = 'Double-click to open the item.'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clGrayText
            Font.Height = -12
            Font.Name = 'Segoe UI'
            Font.Style = []
            ParentFont = False
          end
          object btnAttachSelected: TButton
            Left = 6
            Top = 6
            Width = 170
            Height = 27
            Hint = 'Attach the item selected in the item tree to this hypothesis'
            Caption = 'Attach selected item...'
            ParentShowHint = False
            ShowHint = True
            TabOrder = 0
            OnClick = btnAttachSelectedClick
          end
          object btnDetach: TButton
            Left = 182
            Top = 6
            Width = 90
            Height = 27
            Hint = 'Take the selected item off this hypothesis'
            Caption = 'Remove'
            ParentShowHint = False
            ShowHint = True
            TabOrder = 1
            OnClick = btnDetachClick
          end
        end
      end
      object tsEvidence: TTabSheet
        Caption = 'Evidence'
        ImageIndex = 2
        object lvEvidence: TListView
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 439
          Height = 203
          Align = alClient
          Columns = <
            item
              Caption = 'Item'
              Width = 130
            end
            item
              Caption = 'What'
              Width = 150
            end
            item
              Caption = 'Note'
              Width = 90
            end
            item
              Caption = 'Warning'
              Width = 60
            end>
          HideSelection = False
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
          OnCustomDrawItem = lvEvidenceCustomDrawItem
          OnDblClick = lvEvidenceDblClick
        end
        object pnlEvidenceButtons: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 212
          Width = 439
          Height = 40
          Align = alBottom
          BorderOuter = fsFlatRounded
          TabOrder = 1
          object lblEvidenceHint: TLabel
            Left = 230
            Top = 12
            Width = 146
            Height = 15
            Caption = 'Double-click to open the item.'
            Font.Charset = DEFAULT_CHARSET
            Font.Color = clGrayText
            Font.Height = -12
            Font.Name = 'Segoe UI'
            Font.Style = []
            ParentFont = False
          end
          object btnCite: TButton
            Left = 6
            Top = 6
            Width = 120
            Height = 27
            Hint = 'Cite a run item, one of its files or one of its values'
            Caption = 'Add evidence...'
            ParentShowHint = False
            ShowHint = True
            TabOrder = 0
            OnClick = btnCiteClick
          end
          object btnRemoveEvidence: TButton
            Left = 132
            Top = 6
            Width = 90
            Height = 27
            Hint = 'Take the selected evidence off this hypothesis'
            Caption = 'Remove'
            ParentShowHint = False
            ShowHint = True
            TabOrder = 1
            OnClick = btnRemoveEvidenceClick
          end
        end
      end
      object tsConclusion: TTabSheet
        Caption = 'Conclusion'
        ImageIndex = 3
        object lblConclusionCap: TLabel
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 439
          Height = 15
          Align = alTop
          Caption = 'What we found'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Segoe UI'
          Font.Style = [fsBold]
          ParentFont = False
        end
        object memConclusion: TMemo
          AlignWithMargins = True
          Left = 3
          Top = 24
          Width = 439
          Height = 182
          Align = alClient
          ScrollBars = ssVertical
          TabOrder = 0
          OnChange = memConclusionChange
        end
        object pnlConclusionButtons: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 212
          Width = 439
          Height = 40
          Align = alBottom
          BorderOuter = fsFlatRounded
          TabOrder = 1
          object lblOutcome: TLabel
            Left = 8
            Top = 12
            Width = 43
            Height = 15
            Caption = 'Outcome'
          end
          object cbOutcome: TComboBox
            Left = 64
            Top = 8
            Width = 130
            Height = 23
            Style = csDropDownList
            TabOrder = 0
            OnChange = cbOutcomeChange
            Items.Strings = (
              'Supported'
              'Refuted'
              'Inconclusive')
          end
          object btnSubmit: TButton
            Left = 204
            Top = 6
            Width = 140
            Height = 27
            Hint =
              'Send the conclusion to an approver, who accepts it or returns it' +
              ' for more work'
            Caption = 'Submit conclusion'
            ParentShowHint = False
            ShowHint = True
            TabOrder = 1
            OnClick = btnSubmitClick
          end
        end
      end
      object tsHistory: TTabSheet
        Caption = 'History'
        ImageIndex = 4
        object lvHistory: TListView
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 439
          Height = 249
          Align = alClient
          Columns = <
            item
              Caption = 'When'
              Width = 110
            end
            item
              Caption = 'Who'
              Width = 110
            end
            item
              Caption = 'What'
              Width = 150
            end
            item
              Caption = 'Comment'
              Width = 200
            end>
          ReadOnly = True
          RowSelect = True
          TabOrder = 0
          ViewStyle = vsReport
        end
      end
    end
    object pnlGate: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 385
      Width = 453
      Height = 200
      Align = alBottom
      BorderOuter = fsFlatRounded
      TabOrder = 1
      Visible = False
      object lblGate: TLabel
        AlignWithMargins = True
        Left = 5
        Top = 5
        Width = 443
        Height = 17
        Align = alTop
        Caption = 'Your decision'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -13
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object lblGateHelp1: TLabel
        AlignWithMargins = True
        Left = 5
        Top = 28
        Width = 443
        Height = 15
        Align = alTop
        WordWrap = True
      end
      object lblGateHelp2: TLabel
        AlignWithMargins = True
        Left = 5
        Top = 49
        Width = 443
        Height = 15
        Align = alTop
        WordWrap = True
      end
      object lblGateHint: TLabel
        AlignWithMargins = True
        Left = 5
        Top = 70
        Width = 443
        Height = 15
        Align = alTop
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGrayText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object memGateComment: TMemo
        AlignWithMargins = True
        Left = 5
        Top = 91
        Width = 443
        Height = 60
        Align = alClient
        ScrollBars = ssVertical
        TabOrder = 0
        OnChange = memGateCommentChange
      end
      object pnlGateButtons: TRzPanel
        AlignWithMargins = True
        Left = 5
        Top = 157
        Width = 443
        Height = 38
        Align = alBottom
        BorderOuter = fsFlatRounded
        TabOrder = 1
        object btnGatePrimary: TButton
          Left = 6
          Top = 5
          Width = 160
          Height = 27
          TabOrder = 0
          OnClick = btnGateClick
        end
        object btnGateSecondary: TButton
          Left = 172
          Top = 5
          Width = 160
          Height = 27
          TabOrder = 1
          OnClick = btnGateClick
        end
      end
    end
  end
end
