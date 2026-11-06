unit unit_ReadToolAllowlist;

interface

const
  READ_TOOL_NAMES: array[0..37] of string = (
    'check_storage',
    'check_value_drift',
    'correlate_values',
    'extract_file_data',
    'extract_file_key_values',
    'find_hypotheses_for_item',
    'get_audit_log',
    'get_comments',
    'get_file_columns',
    'get_hypothesis',
    'get_hypothesis_tree',
    'get_item',
    'get_item_links',
    'get_item_tags',
    'get_project_stats',
    'get_protocols',
    'get_series_table',
    'get_signatures',
    'get_values',
    'list_action_types',
    'list_audit_rules',
    'list_equipment',
    'list_file_columns',
    'list_file_types',
    'list_files',
    'list_folders',
    'list_hypotheses',
    'list_items',
    'list_projects',
    'list_series',
    'list_tags',
    'list_users',
    'list_value_types',
    'query_values',
    'report_value_issues',
    'search',
    'search_semantic',
    'wiki_get_page'
  );

implementation

end.
