{{ config(materialized='streaming_table') }}

-- depends_on: {{ source('raw', 'posts') }}

SELECT
  *,
  _metadata.file_name AS _source_file,
  _metadata.file_modification_time AS _file_modified_at
FROM STREAM read_files(
  '/Volumes/{{ env_var("DBX_CATALOG") }}/bronze/landing/posts/',
  format => 'json'
)
