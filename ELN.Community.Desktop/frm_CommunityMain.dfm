object frmCommunityMain: TfrmCommunityMain
  Left = 0
  Top = 0
  Caption = 'ELN Community'
  ClientHeight = 850
  ClientWidth = 1500
  Constraints.MinHeight = 640
  Constraints.MinWidth = 1100
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  GlassFrame.Enabled = True
  Menu = MainMenu
  Position = poScreenCenter
  WindowState = wsMaximized
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  OnCloseQuery = FormCloseQuery
  OnAfterMonitorDpiChanged = FormAfterMonitorDpiChanged
  PixelsPerInch = 96
  TextHeight = 17
  object StatusBar: TRzStatusBar
    AlignWithMargins = True
    Align = alBottom
    Height = 24
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderSides = [sdLeft, sdTop, sdRight, sdBottom]
    BorderWidth = 0
    object StatusNotebook: TRzStatusPane
      AlignWithMargins = True
      Align = alLeft
      Width = 650
      Caption = 'No notebook open'
    end
    object StatusFile: TRzStatusPane
      AlignWithMargins = True
      Align = alClient
      Caption = ''
    end
  end
  object pnlWelcome: TRzPanel
    AlignWithMargins = True
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    OnResize = pnlWelcomeResize
    object lblWelcome: TLabel
      Left = 40
      Top = 48
      Width = 580
      Height = 90
      AutoSize = False
      Caption = 'ELN Community. Create a new local notebook, or open a Community notebook and its attachment directory. A format-2 notebook is upgraded only after you confirm, and a backup is made first.'
      WordWrap = True
    end
    object btnNew: TButton
      Left = 40
      Top = 155
      Width = 210
      Height = 38
      Caption = 'New Notebook...'
      TabOrder = 0
      OnClick = NewNotebookClick
    end
    object btnOpen: TButton
      Left = 265
      Top = 155
      Width = 210
      Height = 38
      Caption = 'Open Notebook...'
      TabOrder = 1
      OnClick = OpenNotebookClick
    end
  end
  object spMain: TRzSplitter
    AlignWithMargins = True
    Align = alClient
    Width = 1494
    Height = 820
    Position = 330
    Percent = 22
    UsePercent = True
    TabOrder = 1
    UpperLeft.Color = 15987699
    LowerRight.Color = 15987699
    Color = 15987699
    Transparent = True
    UpperLeftControls = (
      frmProjects)
    LowerRightControls = (
      spCenter)
    inline frmProjects: TframeProjectTree
      AlignWithMargins = True
      Align = alClient
      Width = 324
      Height = 814
      TabOrder = 0
      inherited pnlMain: TRzPanel
        ParentFont = False
        inherited RzPanel1: TRzPanel
          ParentFont = False
        end
        inherited pnlSearch: TRzPanel
          ParentFont = False
          inherited edSearch: TRzEdit
            ParentFont = False
          end
          inherited btnClearSearch: TRzBitBtn
            ParentFont = False
          end
        end
      end
      inherited pnlBottom: TRzPanel
        ParentFont = False
      end
    end
    object spCenter: TRzSplitter
      AlignWithMargins = True
      Margins.Top = 0
      Margins.Bottom = 0
      Align = alClient
      Width = 1160
      Height = 814
      Position = 500
      Percent = 43
      UsePercent = True
      TabOrder = 0
      UpperLeft.Color = 15987699
      LowerRight.Color = 15987699
      Color = 15987699
      Transparent = True
      UpperLeftControls = (
        frmItems)
      LowerRightControls = (
        spRight)
      inline frmItems: TframeItemTree
        AlignWithMargins = True
        Align = alClient
        Width = 494
        Height = 808
        TabOrder = 0
        inherited pnlBottom: TRzPanel
          ParentFont = False
        end
        inherited pnlMain: TRzPanel
          ParentFont = False
          inherited RzPanel1: TRzPanel
            BorderOuter = fsNone
            ParentFont = False
            inherited pnlSearch: TRzPanel
              ParentFont = False
              inherited btnClearSearch: TRzBitBtn
                ParentFont = False
              end
              inherited edSearch: TRzEdit
                ParentFont = False
              end
            end
            inherited RzPanel2: TRzPanel
              ParentFont = False
            end
          end
        end
        inherited pnlTitle: TRzPanel
          Margins.Top = 3
          ParentFont = False
        end
      end
      object spRight: TRzSplitter
        AlignWithMargins = True
        Margins.Top = 0
        Margins.Bottom = 0
        Align = alClient
        Width = 650
        Height = 808
        Orientation = orVertical
        Position = 610
        Percent = 76
        UsePercent = True
        TabOrder = 0
        UpperLeft.Color = 15987699
        LowerRight.Color = 15987699
        Color = 15987699
        Transparent = True
        UpperLeftControls = (
          frmContentViewer)
        LowerRightControls = (
          FileThumbnailList)
        inline frmContentViewer: TframeContentViewer
          AlignWithMargins = True
          Align = alClient
          Width = 644
          Height = 604
          TabOrder = 0
        end
        object FileThumbnailList: TELNThumbnailList
          AlignWithMargins = True
          Align = alClient
          BorderStyle = bsNone
          VertScrollBar.Visible = False
          TabOrder = 0
        end
      end
    end
  end
  inline frmDashboard: TframeDashboard
    Margins.Top = 0
    Margins.Bottom = 0
    Left = 0
    Top = 0
    Width = 650
    Height = 610
    Visible = False
    TabOrder = 2
  end
  object MainMenu: TMainMenu
    Images = dmTreeImages.vilMenuImages
    Left = 760
    Top = 40
    object miFile: TMenuItem
      Caption = '&File'
      object miNew: TMenuItem
        Caption = '&New Notebook...'
        ImageIndex = 20
        ImageName = 'New'
        OnClick = NewNotebookClick
      end
      object miOpen: TMenuItem
        Caption = '&Open Notebook...'
        ImageIndex = 27
        ImageName = 'Open File'
        OnClick = OpenNotebookClick
      end
      object miCloseNotebook: TMenuItem
        Caption = '&Close Notebook'
        ImageIndex = 2
        ImageName = 'Logout'
        OnClick = CloseNotebookClick
      end
      object miImport: TMenuItem
        Caption = 'Import scientific package...'
        ImageIndex = 1
        ImageName = 'Import'
        Tag = 1
        OnClick = CommandClick
      end
      object miExport: TMenuItem
        Caption = 'Export scientific package...'
        ImageIndex = 0
        ImageName = 'Export'
      end
      object miReport: TMenuItem
        Caption = 'Export report / PDF...'
        ImageIndex = 0
        ImageName = 'Export'
      end
      object miExit: TMenuItem
        Caption = 'E&xit'
        ImageIndex = 3
        ImageName = 'Exit'
        OnClick = ExitClick
      end
    end
    object miProject: TMenuItem
      Caption = '&Project'
      object miNewProject: TMenuItem
        Caption = 'New Project'
        ImageIndex = 20
        ImageName = 'New'
      end
      object miNewGroup: TMenuItem
        Caption = 'New Group'
        ImageIndex = 19
        ImageName = 'Add List'
      end
      object miNewFolder: TMenuItem
        Caption = 'New Folder'
        ImageIndex = 7
        ImageName = 'Add Folder'
      end
      object miTopicWiki: TMenuItem
        Caption = 'New Topic Wiki'
        ImageIndex = 20
        ImageName = 'New'
      end
      object miEditProject: TMenuItem
        Caption = 'Edit'
        ImageIndex = 8
        ImageName = 'Edit'
      end
      object miArchive: TMenuItem
        Caption = 'Archive'
        ImageIndex = 15
        ImageName = 'Archive'
      end
      object miHypotheses: TMenuItem
        Caption = 'Hypotheses'
        ImageIndex = 26
        ImageName = 'Analyze'
      end
      object miDeleteProject: TMenuItem
        Caption = 'Delete'
        ImageIndex = 9
        ImageName = 'Delete Document'
      end
      object miRefreshProjects: TMenuItem
        Caption = 'Refresh'
        ImageIndex = 12
        ImageName = 'Refresh'
      end
      object miArchived: TMenuItem
        Caption = 'Show Archived'
        ImageIndex = 14
        ImageName = 'Show Archived'
      end
    end
    object miItem: TMenuItem
      Caption = '&Item'
      object miProcedure: TMenuItem
        Caption = 'New Procedure'
        ImageIndex = 21
        ImageName = 'New Procedure'
      end
      object miSpecimen: TMenuItem
        Caption = 'New Specimen'
        ImageIndex = 6
        ImageName = 'Add File'
      end
      object miAction: TMenuItem
        Caption = 'New Action'
        ImageIndex = 22
        ImageName = 'New Action'
      end
      object miFromTemplate: TMenuItem
        Caption = 'New from Template...'
        ImageIndex = 29
        ImageName = 'Templates'
      end
      object miAddFile: TMenuItem
        Caption = 'Add File...'
        ImageIndex = 6
        ImageName = 'Add File'
      end
      object miAddNote: TMenuItem
        Caption = 'Add Note...'
        ImageIndex = 23
        ImageName = 'Note'
      end
      object miAddProtocol: TMenuItem
        Caption = 'Add Protocol...'
        ImageIndex = 24
        ImageName = 'Protocol'
      end
      object miAddValue: TMenuItem
        Caption = 'Add Value...'
        ImageIndex = 25
        ImageName = 'Value'
      end
      object miEditItem: TMenuItem
        Caption = 'Edit'
        ImageIndex = 8
        ImageName = 'Edit'
      end
      object miDuplicate: TMenuItem
        Caption = 'Duplicate'
        ImageIndex = 13
        ImageName = 'Duplicate'
      end
      object miLinks: TMenuItem
        Caption = 'Links'
        ImageIndex = 19
      end
      object miDeleteItem: TMenuItem
        Caption = 'Delete'
        ImageIndex = 9
        ImageName = 'Delete Document'
      end
      object miRefreshItems: TMenuItem
        Caption = 'Refresh'
        ImageIndex = 12
        ImageName = 'Refresh'
      end
    end
    object miData: TMenuItem
      Caption = '&Reference Data'
      object miFileTypes: TMenuItem
        Caption = 'File Types...'
        ImageIndex = 32
        ImageName = 'File Types'
        Tag = 10
        OnClick = CommandClick
      end
      object miEquipmentTypes: TMenuItem
        Caption = 'Equipment Types...'
        ImageIndex = 33
        ImageName = 'Equipment Types'
        Tag = 11
        OnClick = CommandClick
      end
      object miEquipment: TMenuItem
        Caption = 'Equipment...'
        ImageIndex = 30
        ImageName = 'Equipment'
        Tag = 12
        OnClick = CommandClick
      end
      object miActionTypes: TMenuItem
        Caption = 'Action Types...'
        ImageIndex = 34
        ImageName = 'Action Types'
        Tag = 13
        OnClick = CommandClick
      end
      object miValueTypes: TMenuItem
        Caption = 'Value Types...'
        ImageIndex = 31
        ImageName = 'Value Types'
        Tag = 14
        OnClick = CommandClick
      end
      object miLinkTypes: TMenuItem
        Caption = 'Link Types...'
        Tag = 15
        OnClick = CommandClick
      end
      object miTemplates: TMenuItem
        Caption = 'Protocol Templates...'
        ImageIndex = 29
        ImageName = 'Templates'
        Tag = 16
        OnClick = CommandClick
      end
      object miExperimentTemplates: TMenuItem
        Caption = 'Experiment Templates...'
        ImageIndex = 29
        ImageName = 'Templates'
        Tag = 17
        OnClick = CommandClick
      end
      object miTags: TMenuItem
        Caption = 'Tags...'
        ImageIndex = 43
        ImageName = 'Tag Editor'
        Tag = 18
        OnClick = CommandClick
      end
    end
    object miTools: TMenuItem
      Caption = '&Tools'
      object miSearch: TMenuItem
        Caption = 'Search...'
        ImageIndex = 52
        ImageName = 'Search'
        Tag = 20
        OnClick = CommandClick
      end
      object miGoTo: TMenuItem
        Caption = 'Go to Item...'
        Tag = 21
        OnClick = CommandClick
      end
      object miDashboard: TMenuItem
        Caption = 'Dashboard'
        ImageIndex = 4
        ImageName = 'Dashboard'
        Tag = 22
        OnClick = CommandClick
      end
      object miAnalysis: TMenuItem
        Caption = 'Analysis...'
        ImageIndex = 37
        ImageName = 'Analysis'
        Tag = 23
        OnClick = CommandClick
      end
      object miUnits: TMenuItem
        Caption = 'Unit Converter...'
        ImageIndex = 39
        ImageName = 'Unit Converter'
        Tag = 24
        OnClick = CommandClick
      end
      object miReview: TMenuItem
        Caption = 'Protocol Review...'
        ImageIndex = 38
        ImageName = 'Protocol Review'
        Tag = 25
        OnClick = CommandClick
      end
      object miAudit: TMenuItem
        Caption = 'Audit Log...'
        ImageIndex = 41
        ImageName = 'Audit Log'
        Tag = 26
        OnClick = CommandClick
      end
      object miAuditRules: TMenuItem
        Caption = 'Completeness Rules...'
        ImageIndex = 61
        ImageName = 'Audit Rules'
        Tag = 27
        OnClick = CommandClick
      end
      object miCompleteness: TMenuItem
        Caption = 'Data Completeness...'
        ImageIndex = 62
        ImageName = 'Data Completeness'
        Tag = 28
        OnClick = CommandClick
      end
      object miRecycle: TMenuItem
        Caption = 'Recycle Bin...'
        ImageIndex = 42
        ImageName = 'Recycle Bin'
        Tag = 29
        OnClick = CommandClick
      end
      object miSaveDraft: TMenuItem
        Caption = 'Save Attachment Working Draft'
        Tag = 30
        OnClick = CommandClick
      end
      object miReloadDraft: TMenuItem
        Caption = 'Reload Attachment Working Draft'
        Tag = 31
        OnClick = CommandClick
      end
      object miPreferences: TMenuItem
        Caption = 'Preferences...'
        ImageIndex = 40
        ImageName = 'Settings'
        OnClick = PreferencesClick
      end
    end
    object miHelp: TMenuItem
      Caption = '&Help'
      object miContents: TMenuItem
        Caption = 'Contents...'
        ImageIndex = 46
        ImageName = 'Manual'
        Tag = 90
        OnClick = CommandClick
      end
      object miShortcuts: TMenuItem
        Caption = 'Keyboard Shortcuts...'
        ImageIndex = 47
        ImageName = 'Keyboard'
        Tag = 91
        OnClick = CommandClick
      end
      object miAbout: TMenuItem
        Caption = 'About...'
        ImageIndex = 50
        ImageName = 'About'
        Tag = 92
        OnClick = CommandClick
      end
    end
  end
  object OpenNotebookDialog: TOpenDialog
    DefaultExt = 'sqlite'
    Filter = 'Community notebook (*.sqlite)|*.sqlite|All files (*.*)|*.*'
    Options = [ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Open Community notebook'
    Left = 820
    Top = 40
  end
  object NewNotebookDialog: TSaveDialog
    DefaultExt = 'sqlite'
    Filter = 'Community notebook (*.sqlite)|*.sqlite'
    Options = [ofPathMustExist, ofEnableSizing]
    Title = 'Create a new Community notebook (existing files are never overwritten)'
    Left = 880
    Top = 40
  end
  object StorageDialog: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Title = 'Choose notebook attachment directory'
    Left = 940
    Top = 40
  end
end
