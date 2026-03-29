# Get Filtered Discovery Feed

A highly optimized read-endpoint powering the Merian global feed.
Handles complex spatial querying, cursor-based pagination, and relational taxonomy filtering. It abstracts the heavy `PostGIS` operations and filtering rules (e.g. only showing `geoprivacy = 'open'`) so the client Swift UI stays perfectly fluid.
