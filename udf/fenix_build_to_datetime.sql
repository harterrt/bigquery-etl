/*
Convert the Fenix client_info.app_build-format string to a DATETIME.
May return NULL on failure.

Fenix originally used an 8-digit app_build format as documented here:
https://github.com/mozilla-mobile/fenix/blob/c72834479eb3e13ee91f82b529e59aa08392a92d/automation/gradle/versionCode.gradle#L13

In short it is yDDDHHmm
 * y is years since 2018
 * DDD is day of year, 0-padded, 001-366
 * HH is hour of day, 00-23
 * mm is minute of hour, 00-59

The last date seen with an 8-digit build ID is 2020-08-10.

Newer builds use a 10-digit format where the integer represents a pattern
consisting of 32 bits. The 17 bits starting 13 bits from the left represent
a number of hours since UTC midnight beginning 2014-12-28, although the
documented format intends a later epoch, so this format may need to change again.
See https://github.com/mozilla-mobile/fenix/issues/14031

This function tolerates both formats.

After using this you may wish to DATETIME_TRUNC(result, DAY) for grouping
by build date.

*/
CREATE OR REPLACE FUNCTION udf.fenix_build_to_datetime(app_build STRING) AS (
  CASE
    LENGTH(app_build)
  WHEN
    8
  THEN
    DATETIME_ADD(
      DATETIME_ADD(
        DATETIME_ADD(
          DATETIME_ADD(
            DATETIME '2018-01-01 00:00:00',
            INTERVAL SAFE_CAST(SUBSTR(app_build, 1, 1) AS INT64) YEAR
          ),
          INTERVAL SAFE_CAST(SUBSTR(app_build, 2, 3) AS INT64) - 1 DAY
        ),
        INTERVAL SAFE_CAST(SUBSTR(app_build, 5, 2) AS INT64) HOUR
      ),
      INTERVAL SAFE_CAST(SUBSTR(app_build, 7, 2) AS INT64) MINUTE
    )
  WHEN
    10
  THEN
    DATETIME_ADD(
      DATETIME '2014-12-28 00:00:00',
      INTERVAL(
        SAFE_CAST(app_build AS INT64)
        -- We shift left and then right again to erase all but the 20 rightmost bits
        << (64 - 20) >> (64 - 20)
        -- We then shift right to erase the last 3 bits, leaving just the 17 representing time
        >> 3
      ) HOUR
    )
  ELSE
    NULL
  END
);

-- Tests
SELECT
  assert_equals(DATETIME '2020-06-05 14:34:00', udf.fenix_build_to_datetime("21571434")),
  assert_equals(DATETIME '2020-08-13 04:00:00', udf.fenix_build_to_datetime("2015757667")),
  assert_null(udf.fenix_build_to_datetime("3")),
  assert_null(udf.fenix_build_to_datetime("hi"))
