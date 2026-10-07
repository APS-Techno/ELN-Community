object dlgNote: TdlgNote
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Edit Note'
  ClientHeight = 300
  ClientWidth = 395
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 13
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 395
    Height = 255
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblTitle: TRzLabel
      Left = 12
      Top = 8
      Width = 24
      Height = 13
      Caption = 'Title:'
    end
    object edtTitle: TRzEdit
      Left = 12
      Top = 24
      Width = 376
      Height = 21
      Text = ''
      TabOrder = 0
    end
    object pnlToolbar: TRzPanel
      Left = 12
      Top = 50
      Width = 376
      Height = 20
      BorderOuter = fsFlatRounded
      TabOrder = 1
      Color = clBtnFace
      object btnBold: TRzButton
        Left = 0
        Top = 0
        Width = 30
        Height = 18
        Caption = 'B'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = [fsBold]
        ParentFont = False
        TabOrder = 0
        OnClick = btnBoldClick
      end
      object btnItalic: TRzButton
        Left = 33
        Top = 0
        Width = 30
        Height = 18
        Caption = 'I'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = [fsItalic]
        ParentFont = False
        TabOrder = 1
        OnClick = btnItalicClick
      end
      object btnUnderline: TRzButton
        Left = 66
        Top = 0
        Width = 30
        Height = 18
        Caption = 'U'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = [fsUnderline]
        ParentFont = False
        TabOrder = 2
        OnClick = btnUnderlineClick
      end
    end
    object reContent: TRichEdit
      Left = 12
      Top = 73
      Width = 376
      Height = 174
      Font.Charset = ANSI_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssVertical
      TabOrder = 2
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 255
    Width = 395
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnOK: TRzButton
      Left = 237
      Top = 10
      Default = True
      Caption = 'OK'
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TRzButton
      Left = 318
      Top = 10
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
end
