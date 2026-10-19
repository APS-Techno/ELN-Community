object dlgDerivedValue: TdlgDerivedValue
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Add Derived Value'
  ClientHeight = 420
  ClientWidth = 640
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCloseQuery = FormCloseQuery
  TextHeight = 15
  object pnlButtons: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 376
    Width = 634
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 557
      Top = 8
      ModalResult = 1
      Caption = 'Save'
      Enabled = False
      TabOrder = 0
    end
    object btnCancel: TRzBitBtn
      Left = 8
      Top = 8
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 634
    Height = 367
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblFormula: TRzLabel
      Left = 8
      Top = 8
      Width = 48
      Height = 17
      Caption = 'Formula'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblExpression: TRzLabel
      Left = 8
      Top = 74
      Width = 618
      Height = 17
      AutoSize = False
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblRoles: TRzLabel
      Left = 8
      Top = 98
      Width = 300
      Height = 17
      AutoSize = False
      Caption = 'Inputs: select a role, then a stored value'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblCandidates: TRzLabel
      Left = 318
      Top = 98
      Width = 308
      Height = 17
      AutoSize = False
      Caption = 'Stored values with the required type and unit'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblResult: TRzLabel
      Left = 8
      Top = 276
      Width = 618
      Height = 34
      AutoSize = False
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Transparent = True
      WordWrap = True
    end
    object lblDescription: TRzLabel
      Left = 8
      Top = 314
      Width = 66
      Height = 17
      Caption = 'Description'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lbFormula: TListBox
      Left = 8
      Top = 28
      Width = 618
      Height = 42
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      StyleElements = [seClient, seBorder]
      TabOrder = 0
      OnClick = lbFormulaClick
    end
    object lbRoles: TListBox
      Left = 8
      Top = 118
      Width = 300
      Height = 152
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      StyleElements = [seClient, seBorder]
      TabOrder = 1
      OnClick = lbRolesClick
    end
    object lbCandidates: TListBox
      Left = 318
      Top = 118
      Width = 308
      Height = 152
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      StyleElements = [seClient, seBorder]
      TabOrder = 2
      OnClick = lbCandidatesClick
    end
    object edDescription: TRzEdit
      Left = 8
      Top = 334
      Width = 618
      Height = 23
      Text = ''
      TabOrder = 3
    end
  end
end
