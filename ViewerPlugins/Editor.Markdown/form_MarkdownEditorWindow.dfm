object formMarkdownEditor: TformMarkdownEditor
  Left = 0
  Top = 0
  Caption = 'Markdown Editor'
  ClientHeight = 750
  ClientWidth = 1100
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDesigned
  KeyPreview = True
  OnClose = FormClose
  OnCreate = FormCreate
  OnCloseQuery = FormCloseQuery
  OnKeyDown = FormKeyDown
  TextHeight = 15
  object pnlTop: TRzPanel
    Left = 0
    Top = 0
    Width = 1100
    Height = 64
    Align = alTop
    BorderOuter = fsNone
    TabOrder = 0
    object tbActions: TRzToolbar
      Left = 0
      Top = 0
      Width = 220
      Height = 64
      Align = alLeft
      AutoStyle = False
      RowHeight = 30
      AutoSize = False
      BorderInner = fsNone
      BorderOuter = fsNone
      BorderWidth = 0
      TabOrder = 0
      ToolbarControls = (
        btnSave
        btnReload)
      object btnSave: TRzToolButton
        Left = 6
        Top = 5
        Width = 70
        Hint = 'Save (Ctrl+S)'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'Save'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoSaveClick
      end
      object btnReload: TRzToolButton
        Left = 78
        Top = 5
        Width = 80
        Hint = 'Reload from disk'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'Reload'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoReloadClick
      end
    end
    object tbFormat: TRzToolbar
      Left = 220
      Top = 0
      Width = 640
      Height = 64
      Align = alClient
      AutoStyle = False
      RowHeight = 30
      AutoSize = False
      BorderInner = fsNone
      BorderOuter = fsNone
      BorderWidth = 0
      TabOrder = 1
      ToolbarControls = (
        btnBold
        btnItalic
        btnHeading
        btnList
        btnCode
        btnLink
        btnImage)
      object btnBold: TRzToolButton
        Left = 6
        Top = 5
        Width = 40
        Hint = 'Bold (Ctrl+B)'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'B'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoBoldClick
      end
      object btnItalic: TRzToolButton
        Left = 48
        Top = 5
        Width = 40
        Hint = 'Italic (Ctrl+I)'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'I'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoItalicClick
      end
      object btnHeading: TRzToolButton
        Left = 90
        Top = 5
        Width = 40
        Hint = 'Heading'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'H'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoHeadingClick
      end
      object btnList: TRzToolButton
        Left = 132
        Top = 5
        Width = 60
        Hint = 'Bullet list'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = '- List'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoListClick
      end
      object btnCode: TRzToolButton
        Left = 194
        Top = 5
        Width = 50
        Hint = 'Inline code'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = '</>'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoCodeClick
      end
      object btnLink: TRzToolButton
        Left = 246
        Top = 5
        Width = 60
        Hint = 'Insert link (Ctrl+K)'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'Link'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoLinkClick
      end
      object btnImage: TRzToolButton
        Left = 308
        Top = 5
        Width = 60
        Hint = 'Insert image'
        UseToolbarShowCaption = False
        ShowCaption = True
        Caption = 'Img'
        ParentShowHint = False
        ShowHint = True
        OnClick = DoImageClick
      end
    end
    object rgMode: TRzRadioGroup
      Left = 860
      Top = 0
      Width = 240
      Height = 64
      Align = alRight
      Caption = ''
      Columns = 3
      ItemIndex = 0
      Items.Strings = (
        'Source'
        'Preview'
        'Split')
      TabOrder = 2
      OnClick = DoModeChange
    end
  end
  object sbStatus: TRzStatusBar
    Left = 0
    Top = 731
    Width = 1100
    Height = 19
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderWidth = 0
    TabOrder = 1
    object pneFile: TRzStatusPane
      Left = 0
      Top = 0
      Width = 300
      Height = 19
      Align = alLeft
      Caption = ''
    end
    object pneChars: TRzStatusPane
      Left = 300
      Top = 0
      Width = 120
      Height = 19
      Align = alLeft
      Caption = '0 chars'
    end
    object pneState: TRzStatusPane
      Left = 420
      Top = 0
      Width = 200
      Height = 19
      Align = alLeft
      Caption = ''
    end
  end
  object splPreview: TSplitter
    Left = 1095
    Top = 64
    Width = 5
    Height = 667
    Align = alRight
    Visible = False
    ExplicitLeft = 0
    ExplicitTop = 0
    ExplicitHeight = 100
  end
  object pnlPreview: TPanel
    Left = 545
    Top = 64
    Width = 550
    Height = 667
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 2
    Visible = False
  end
  object edSrc: TSynEdit
    Left = 0
    Top = 64
    Width = 545
    Height = 667
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -15
    Font.Name = 'Consolas'
    Font.Style = []
    TabOrder = 3
    Gutter.ShowLineNumbers = True
    WantTabs = True
    TabWidth = 2
  end
end
