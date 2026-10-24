SELECT
  id AS post_id,
  userId AS user_id,
  title,
  body
FROM {{ ref('posts') }}
