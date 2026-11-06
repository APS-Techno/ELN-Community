object dlgSeriesPlan: TdlgSeriesPlan
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Series plan'
  ClientHeight = 773
  ClientWidth = 640
  Constraints.MinHeight = 693
  Constraints.MinWidth = 560
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  TextHeight = 15
  object pnlGeneral: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 634
    Height = 194
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblGeneral: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Series - what it tests and where its depositions go'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblTitle: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 26
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Title'
    end
    object edTitle: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 47
      Width = 624
      Height = 23
      Align = alTop
      MaxLength = 255
      TabOrder = 0
    end
    object lblPurpose: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 76
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Purpose - what this series tests'
    end
    object memPurpose: TMemo
      AlignWithMargins = True
      Left = 5
      Top = 97
      Width = 624
      Height = 40
      Align = alTop
      ScrollBars = ssVertical
      TabOrder = 1
    end
    object lblFolder: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 143
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Target folder - where depositions made from the plan are created'
    end
    object cbFolder: TComboBox
      AlignWithMargins = True
      Left = 5
      Top = 164
      Width = 624
      Height = 23
      Align = alTop
      Style = csDropDownList
      DropDownCount = 16
      TabOrder = 2
    end
  end
  object pnlFactors: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 203
    Width = 634
    Height = 134
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object lblFactors: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Factors - parameters you vary (one or two)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblFactorNote: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 101
      Width = 624
      Height = 15
      Align = alBottom
      Caption = 'Remove all points to change the factors. You can still edit their labels.'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Visible = False
    end
    object pnlFactorButtons: TPanel
      AlignWithMargins = True
      Left = 535
      Top = 26
      Width = 94
      Height = 69
      Align = alRight
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      object btnFactorAdd: TButton
        AlignWithMargins = True
        Left = 0
        Top = 0
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Add...'
        TabOrder = 0
        OnClick = AddClick
      end
      object btnFactorEdit: TButton
        AlignWithMargins = True
        Left = 0
        Top = 26
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Edit...'
        TabOrder = 1
        OnClick = EditClick
      end
      object btnFactorRemove: TButton
        AlignWithMargins = True
        Left = 0
        Top = 52
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Remove'
        TabOrder = 2
        OnClick = RemoveClick
      end
    end
    object lvFactors: TListView
      AlignWithMargins = True
      Left = 5
      Top = 26
      Width = 524
      Height = 69
      Align = alClient
      Columns = <
        item
          Caption = 'Value type'
          Width = 150
        end
        item
          Caption = 'Label'
          Width = 220
        end
        item
          Caption = 'Range'
          Width = 130
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      TabOrder = 1
      ViewStyle = vsReport
      OnDblClick = ListDblClick
      OnSelectItem = ListSelectItem
    end
  end
  object pnlLevels: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 343
    Width = 634
    Height = 140
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object lblLevelsHint: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 624
      Height = 30
      Align = alTop
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      WordWrap = True
    end
    object lblLevelsA: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 41
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Levels'
    end
    object edLevelsA: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 62
      Width = 624
      Height = 23
      Align = alTop
      TabOrder = 0
      TextHint = '100; 200; 300'
    end
    object lblLevelsB: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 91
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Levels'
    end
    object edLevelsB: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 112
      Width = 624
      Height = 23
      Align = alTop
      TabOrder = 1
      TextHint = '1; 2; 3'
    end
  end
  object pnlFixed: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 489
    Width = 634
    Height = 112
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 3
    object lblFixed: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Fixed conditions - held constant'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object pnlFixedButtons: TPanel
      AlignWithMargins = True
      Left = 535
      Top = 26
      Width = 94
      Height = 69
      Align = alRight
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      object btnFixedAdd: TButton
        AlignWithMargins = True
        Left = 0
        Top = 0
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Add...'
        Tag = 1
        TabOrder = 0
        OnClick = AddClick
      end
      object btnFixedEdit: TButton
        AlignWithMargins = True
        Left = 0
        Top = 26
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Edit...'
        Tag = 1
        TabOrder = 1
        OnClick = EditClick
      end
      object btnFixedRemove: TButton
        AlignWithMargins = True
        Left = 0
        Top = 52
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Remove'
        Tag = 1
        TabOrder = 2
        OnClick = RemoveClick
      end
    end
    object lvFixed: TListView
      AlignWithMargins = True
      Left = 5
      Top = 26
      Width = 524
      Height = 69
      Align = alClient
      Columns = <
        item
          Caption = 'Value type'
          Width = 150
        end
        item
          Caption = 'Label'
          Width = 180
        end
        item
          Caption = 'Value'
          Width = 90
        end
        item
          Caption = 'Tol'
          Width = 80
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      Tag = 1
      TabOrder = 1
      ViewStyle = vsReport
      OnDblClick = ListDblClick
      OnSelectItem = ListSelectItem
    end
  end
  object pnlResponses: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 607
    Width = 634
    Height = 106
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 4
    object lblResponses: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 624
      Height = 15
      Align = alTop
      Caption = 'Responses - results you measure on each point'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object pnlResponseButtons: TPanel
      AlignWithMargins = True
      Left = 535
      Top = 26
      Width = 94
      Height = 59
      Align = alRight
      BevelOuter = bvNone
      ShowCaption = False
      TabOrder = 0
      object btnResponseAdd: TButton
        AlignWithMargins = True
        Left = 0
        Top = 0
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Add...'
        Tag = 2
        TabOrder = 0
        OnClick = AddClick
      end
      object btnResponseEdit: TButton
        AlignWithMargins = True
        Left = 0
        Top = 26
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Edit...'
        Tag = 2
        TabOrder = 1
        OnClick = EditClick
      end
      object btnResponseRemove: TButton
        AlignWithMargins = True
        Left = 0
        Top = 52
        Width = 94
        Height = 23
        Margins.Left = 0
        Margins.Top = 0
        Margins.Right = 0
        Align = alTop
        Caption = 'Remove'
        Tag = 2
        TabOrder = 2
        OnClick = RemoveClick
      end
    end
    object lvResponses: TListView
      AlignWithMargins = True
      Left = 5
      Top = 26
      Width = 524
      Height = 59
      Align = alClient
      Columns = <
        item
          Caption = 'Value type'
          Width = 150
        end
        item
          Caption = 'Label'
          Width = 350
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      Tag = 2
      TabOrder = 1
      ViewStyle = vsReport
      OnDblClick = ListDblClick
      OnSelectItem = ListSelectItem
    end
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 725
    Width = 634
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 5
    object btnOK: TButton
      Left = 442
      Top = 9
      Width = 90
      Height = 27
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TButton
      Left = 538
      Top = 9
      Width = 90
      Height = 27
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
end
