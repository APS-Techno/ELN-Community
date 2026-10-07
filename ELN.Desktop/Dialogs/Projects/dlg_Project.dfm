object dlgProject: TdlgProject
  Left = 0
  Top = 0
  ActiveControl = edTitle
  BorderStyle = bsDialog
  Caption = 'Project'
  ClientHeight = 185
  ClientWidth = 459
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 453
    Height = 132
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object RzLabel1: TRzLabel
      Left = 8
      Top = 15
      Width = 65
      Height = 17
      Caption = 'Project title'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object RzLabel2: TRzLabel
      Left = 8
      Top = 76
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
    object edTitle: TRzEdit
      Left = 8
      Top = 39
      Width = 427
      Height = 23
      Text = ''
      TabOrder = 0
      OnKeyDown = edTitleKeyDown
    end
    object edComment: TRzEdit
      Left = 8
      Top = 99
      Width = 427
      Height = 23
      Text = ''
      TabOrder = 1
      OnKeyDown = edTitleKeyDown
    end
    object cbArchived: TCheckBox
      Left = 340
      Top = 15
      Width = 95
      Height = 17
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Archived'
      TabOrder = 2
      Visible = False
    end
  end
  object RzPanel2: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 141
    Width = 453
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 360
      Top = 8
      ModalResult = 1
      Caption = 'Save'
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
end
