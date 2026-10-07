object dlgHypothesisEdit: TdlgHypothesisEdit
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Hypothesis'
  ClientHeight = 470
  ClientWidth = 560
  Constraints.MinHeight = 400
  Constraints.MinWidth = 460
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  TextHeight = 15
  object lblTitle: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 554
    Height = 15
    Align = alTop
    Caption = 'Title'
  end
  object edTitle: TEdit
    AlignWithMargins = True
    Left = 3
    Top = 24
    Width = 554
    Height = 23
    Align = alTop
    MaxLength = 255
    TabOrder = 0
  end
  object lblStatement: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 53
    Width = 554
    Height = 15
    Align = alTop
    Caption = 'Statement - what you expect, and why'
  end
  object memStatement: TMemo
    AlignWithMargins = True
    Left = 3
    Top = 74
    Width = 554
    Height = 150
    Align = alTop
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object lblChange: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 230
    Width = 554
    Height = 15
    Align = alTop
    Caption = 'Change - what differs from the parent hypothesis'
  end
  object memChange: TMemo
    AlignWithMargins = True
    Left = 3
    Top = 251
    Width = 554
    Height = 100
    Align = alClient
    ScrollBars = ssVertical
    TabOrder = 2
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 357
    Width = 554
    Height = 110
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 3
    object lblKeyValue: TLabel
      Left = 8
      Top = 8
      Width = 300
      Height = 15
      Caption = 'Headline quantity (optional) - summarised over runs'
    end
    object cbKeyValue: TComboBox
      Left = 8
      Top = 28
      Width = 330
      Height = 23
      Style = csDropDownList
      TabOrder = 0
    end
    object btnOK: TButton
      Left = 360
      Top = 72
      Width = 90
      Height = 27
      Caption = 'OK'
      Default = True
      TabOrder = 1
      OnClick = btnOKClick
    end
    object btnCancel: TButton
      Left = 456
      Top = 72
      Width = 90
      Height = 27
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
end
