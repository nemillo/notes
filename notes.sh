#!/bin/sh

NOTES="notes"
# Note: Depending on your language this folder may have a different name
EXPORT_FOLDER="."
EXPORT="$EXPORT_FOLDER/notes-$(date "+%Y-%m-%d").md"
KEEP=21

DB="KoboReader.sqlite"
SQLITE="sqlite3"

mkdir -p "$(dirname "$EXPORT_FOLDER")"

echo -e "# Kobo Notes\n" > $EXPORT
echo -e "*$(date -R)*\n" >> $EXPORT
echo -e "## Highlights\n" >> $EXPORT

# UTF-8 char table (decimal):
#      9: Tab
#     10: Line feed
#     32: Space
#     58: :
#     62: >
#     42: *
#     92: \
#   8230: …
#   9999: ✏
# 128278: 🔖
# 128196: 📄

SQL="SELECT TRIM(
  '### ' ||
  CASE
    WHEN b.Type = 'dogear' THEN
      char(128278, 32)
    WHEN b.Type = 'note' THEN
      char(9999, 32)
    WHEN b.Type = 'highlight' THEN
      char(128196, 32)
  END
  || c.BookTitle || ', ' || COALESCE(c1.Attribution, 'N/A') || char(10, 10, 42)
  || datetime(b.dateCreated) || char(42, 92, 10) /* force Markdown newline */
  || c.Title || char(10, 10, 62, 32) ||
  CASE
    WHEN b.Type = 'dogear' THEN
      COALESCE(ContextString, 'No context available') || char(8230, 10) /* only kepubs have context */
    ELSE
      REPLACE(              /* start Markdown quote */
        REPLACE(
          TRIM(             /* trim newlines */
            TRIM(           /* trim tabs */
              TRIM(b.Text), /* trim spaces */
              char(9)
            ),
            char(10)
          ),
          char(9), ''
        ),
        char(10), char(10, 62, 32, 10, 62, 32)) /* continue Markdown quote for multiple paragraphs */
      || char(10, 10)
      || COALESCE(b.Annotation, '') || char(10)
  END, char(10)
  ) || char(10, 10)
  FROM Bookmark b
    JOIN Content c ON b.VolumeID = c.BookID
    JOIN Content c1 ON c.BookID = c1.ContentID
  WHERE b.Hidden = 'false'
    AND ((c.MimeType NOT IN ('application/xhtml+xml', /* epub */
                             'application/x-kobo-epub+zip')
          AND c.ContentID = b.ContentID)
        OR (c.MimeType IN ('application/xhtml+xml',   /* kepub */
                           'application/x-kobo-epub+zip')
            AND c.ContentType = 899
            AND c.ContentID LIKE b.ContentID || '-%'))
  ORDER BY c.BookTitle ASC,
           c.VolumeIndex ASC,
           b.ChapterProgress ASC,
           b.DateCreated ASC;"

$SQLITE "$DB" "$SQL" >> $EXPORT

echo -e "## Book progress\n" >> $EXPORT

echo -e "Currently reading:\n" >> $EXPORT

SQL="SELECT
  '- ' || c.Title || COALESCE(', ' || c.Attribution, '')
  || ' (' || COALESCE(c1.Title || ', ', '') || c.___PercentRead || '% read' || ')'
  FROM Content c
  LEFT OUTER JOIN Content c1 ON (
    c.ContentID = c1.BookID
    AND c1.ContentType = 899
    AND REPLACE(c1.ContentID, '!', '/') LIKE /* get chapter id without anchor or query string */
      '%' || SUBSTR(c.ChapterIDBookmarked, 1, INSTR(c.ChapterIDBookmarked, '#') + INSTR(c.ChapterIDBookmarked, '?') - 1) || '%'
  )
  WHERE c.ContentType = 6
    AND c.ReadStatus = 1
    AND c.IsDownloaded = 'true'
  ORDER BY c.___PercentRead DESC,
           c.Title ASC,
           c.Attribution ASC;"

$SQLITE "$DB" "$SQL" >> $EXPORT

# Clean up old notes
cd "$EXPORT_FOLDER"
for i in $(ls -v notes* | head -n -$KEEP); do
  rm "$i"
done
