#!/usr/bin/perl
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::Web::Module;

# NOTE: Example Usage:
# APPCORE_CONFIG=/opt/drivelink/conf/appcore.conf.pl perl schema_to_class.pl iti.accident_otherparties > out.txt && edit out.txt


my $table = $ARGV[0] || die "Usage: $0 table\nor $0 db.table\n";

my $db = $AppCore::Config::DB_NAME;

($db,$table) = split /\./, $table if $table =~ /\./;


AppCore::DBI::mysql_extract_current_schema($db,$table,{dump=>1})

	# Function: mysql_extract_current_schema
	# Simple utility function to export the schmea for a table from MySQL.
	# If {dump=>1} is passed in the $opts ref, it will print to STDOUT code as a perl call to mysql_schema_update($db,$table,$fields)
	# Example usage:  perl -MAppCore::DBI -e "mysql_extract_current_schema('pci','widget_notes_data',{dump=>1})" > out.txt
	# Or, for a bulk dump of a list of tables and generate packages, dumping each table to its own file:
	#  for i in `echo comments posts post_likes comment_likes read_flags read_post_flags read_comment_flags post_tags`; do(echo Dumping $i ...; perl -Mlib='lib' -MAppCore::DBI -e "AppCore::DBI::mysql_extract_current_schema('jblog','$i',{dump=>1,host=>'database',user=>'root',pass=>'...',pkg=>'BryanBlogs::$i'})"  > "dump_$i.txt"); done;