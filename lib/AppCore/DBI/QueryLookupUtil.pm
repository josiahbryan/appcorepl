#!/usr/bin/env perl
use strict;

# use lib '/opt/helpdesk.rc.edu/lib';
# BEGIN {require '/opt/helpdesk.rc.edu/conf/appcore.pl' };
# 
# 
# BEGIN {
# 	use RC::CAMS;
# 	#$RC::CAMS::DB = 'CAMs_Enterprise';
# };

package AppCore::DBI::QueryLookupUtil;
{
	use strict;
	#use RC::CAMS;
	use AppCore::Common;

	# This class was created as a quick-and-dirty way to provide string lookup/validation
	# for my apps that I have to use with Microsoft SQL because I don't have time to get
	# AppCore::DBI->validate_string() working with the buggy Sybase driver. (For example,
	# rows() always returns -1 even with results - and validate_string() and friends in 
	# AppCore::DBI uses rows() heavily internally to decide various code paths to take.)
	
	# NOTE:
	# You can use this either as an object or as functions.
	# If using either of the methods (autocomplete_string) as function, 
	# call as AppCore::DBI::QueryLookupUtil->autocomplete_string($opts, ...)
	# Otherwise, if object, call as $object->autocomplete_string(...)
	# Either way, $opts is expected to look like the following examples:
	
# 	my $opts_colleges = {
#		dbi	=> 'RC::CAMS',
# 		sql	=> q{
# 
# 			select CollegeID, CollegeName, City, States.DisplayText as State
# 			from Colleges c
# 				left outer join Glossary States on States.UniqueId = c.StateID
# 			where CollegeName <> ''
# 				and CollegeName not like '@%'
# 			order by CollegeName
# 		},
# 		
# 		id_col		=> 'collegeid',
# 		string_col	=> q{CollegeName+' - '+City+', '+State},
# 	};
# 
# 	my $opts_highschools = {
#		dbi	=> 'RC::CAMS',
# 		sql	=> q{
# 		
# 			select HighSchoolID, HighschoolName, City, States.DisplayText as State
# 			from HighSchools hs
# 				left outer join Glossary States on States.UniqueId = hs.StateID
# 			where HighschoolName <> ''
# 				and HighSchoolName not like '@%'
# 			order by HighSchoolName
# 			
# 		},
# 		
# 		id_col		=> 'highschoolid',
# 		string_col	=> q{HighschoolName+' - '+City+', '+State},
# 	};

	sub new
	{
		my $class = shift;
		my $opts = shift;
		return bless $opts, $class;
	}

	#my $valid = RC::QueryLookupUtil->validate_string($opts_highschools, 'A beka vid');
	#my @ac    = RC::QueryLookupUtil->autocomplete_string($opts_highschools, 'A bek');
	
	#print Dumper $valid, \@ac;
	
# 	my $vref = AppCore::DBI::QueryLookupUtil->new($opts_highschools);
# 	my @ac    = $vref->autocomplete_string('A bek');
# 	print Dumper \@ac;
	

	sub validate_string 
	{
		my $class = shift;
		my $opts = ref $class ? $class : shift;
		my $string = shift;
		my $id_val = shift;
		my $str_val = shift;
		
		return undef if !$string;
		
		my $dbi = $opts->{dbi} || 'AppCore::DBI';
		my $sql_orig = $opts->{sql};
		my $string_col = $opts->{string_col};
		my $id_col = $opts->{id_col};
		
		$sql_orig =~ s/(\s+order by .*(\n|$))//gi;
		my $order_by = $1;
		#die Dumper $order_by, $sql_orig;
		
		# Since MSSQL doesnt support "sth->rows", use "top 2" and only consider valid if no second row
		my $sql = "select top 2 $id_col as value, $string_col as text from ($sql_orig) tmp where $string_col like ? $order_by";
		#print "__PACKAGE__->validate_string('$string'): $sql\n";
		
		my $sth = $dbi->dbh->prepare_cached($sql, undef, 1);
		$sth->execute('%'.$string.'%');
		
		my @tmp_list;
		push @tmp_list, $_ while $_ = $sth->fetchrow_hashref;
		
		return @tmp_list && @tmp_list == 1 ? shift @tmp_list : undef;
	}

	sub autocomplete_string
	{
		my $class = shift;
		my $opts = ref $class ? $class : shift;
		my $string = shift;
		my $limit = shift || 100;
		my $proper_case = shift;
		$proper_case = 1 if !defined $proper_case;
		
		my @autocomplete_list;
		
		return () if !$string;
		
		my $dbi = $opts->{dbi} || 'AppCore::DBI';
		my $sql_orig = $opts->{sql};
		my $string_col = $opts->{string_col};
		my $id_col = $opts->{id_col};
		
		$sql_orig =~ s/(\s+order by .*(\n|$))//gi;
		my $order_by = $1;
		
		my $sql = "select top $limit $id_col as value, $string_col as text from ($sql_orig) tmp where $string_col like ? $order_by";
		#print "__PACKAGE__->autocomplete_string('$string'): $sql\n";
		
		my $sth = $dbi->dbh->prepare_cached($sql, undef, 1);
		$sth->execute('%'.$string.'%');
		
		push @autocomplete_list, $_ while $_ = $sth->fetchrow_hashref;
		
		if($proper_case)
		{
			@autocomplete_list =
				map { $_->{text} = guess_title(lc($_->{text})); $_ }
				@autocomplete_list;
		}
		
		return @autocomplete_list;
	}
};







