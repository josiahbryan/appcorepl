#!/bin/sh
echo Importing from ./phc-boards.sql ...
mysql -u root -p -h localhost -D appcore < phc-boards.sql

echo Migrating data fields using ./mods/ThemePHC/phc-migrate.sql ...
mysql -u root -p -h localhost -D appcore < mods/ThemePHC/phc-migrate.sql

echo Re-syncing schema ...
bin/flush_db.pl

echo Done.
