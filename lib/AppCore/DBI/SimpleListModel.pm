use strict;


# Package: AppCore::DBI::SimpleListModel
# Simple List Modeling based on AppCore::DBI-derived classes.
# Really just designed to be subclassed rather than used directly.
package AppCore::DBI::SimpleListModel;
{
	use strict;
	use Data::Dumper;
	
	use AppCore::Common;
	
	our $MIN_TERMOID_LENGTH = 3;
	
	sub new
	{
		my $class = shift;
		my $cdbi_class = shift;
		return bless {cdbi_class=>$cdbi_class}, $class;
	}

	# Method: set_filter($string)
	# Set $string as the $string to search for when compiling the list and only return entries in the list that contain $string
	sub set_filter($string)
	{
		my $self = shift;
		my $filter = shift;
		
		# If the filter was set via a multiple <select> box, then split the value on \0
		# so it looks like a space-seprated string to the rest of the model
		$filter =~ s/\0/ /g;
		
		$self->{filter} = $filter;
	}
	
	# Method: filter()
	# Return the $string searched for
	sub filter {shift->{filter}}
	
	# Method: set_sort_column($sort_col)
	# Set column named $sort_col as the column by wich to order the results returned by compile_list(...)
	# Returns 1 if $sort_col is undef (and clears the current sort column)
	# Returns undef and sets $@ to an error message if $sort_col is not a valid column name (as determined by the cdbi_class()'s field_meta() method).
	# Returns the column name if the call was successful.
	sub set_sort_column($sort_col)
	{
		my $self = shift;
		my $sort_col = shift;
		if(!$sort_col)
		{
			undef $self->{sort_column};
			return 1;
		}
		
		my $check_data = $self->cdbi_class->field_meta($sort_col);
		if(!$check_data)
		{
			warn $@ = "[WARN] $self: set_sort_column('$sort_col'): Not setting sort column to '$sort_col' because CDBI class '".$self->cdbi_class."' doesn't have any field_meta() for that column";
			return undef;
		}
		
		$self->{sort_column} = $sort_col;
		
		return $sort_col;
	}
	
	# Method: set_sort_direction($dir)
	# Set the sort direction for the model.
	# Returns 1 if $dir is false or undef (clears the internal sort direction parameter), undef (and sets $@) if $dir is not one of 'asc' or 'desc' (case insensitive), otherwise returns 
	# the lowercase normalized string, one of 'asc' or 'desc'.
	sub set_sort_direction($dir)
	{
		my $self = shift;
		my $dir  = shift;
		if(!$dir)
		{
			undef $self->{sort_direction};
			return 1;
		}
		my $norm_dir = $dir eq 'asc' ? 'asc' : $dir eq 'desc' ? 'desc' : undef;
		if(!$norm_dir)
		{
			warn $@ = "[WARN] $self: set_sort_direction('$dir'): Not setting sort direction because '$dir' is not one of 'asc' or 'desc'. (Argument is case insensitive)";
			return undef;
		}
		
		$self->{sort_direction} = $norm_dir;
		
		return $norm_dir;
	}
	
	# Method: sort_column()
	# Returns the name of the current sort column
	sub sort_column    { shift->{sort_column} }
	
	# Method: sort_direction()
	# Returns the string 'asc' or 'desc' representing the current sort direction
	sub sort_direction { shift->{sort_direction} }
	
	# Method: columns()
	# Returns a list (not a listref) of hashrefs describing the columns available in the cdbi_class().
	# Note: To set which columns are returned in the data from compile_list(), use set_list_columns()
	sub columns { return @{ shift->cdbi_class->meta->{schema} || [] } }
	
	# Method: list_columns()
	# Return the list of columns that you want to see in the reults - defaults to all columns.
	sub list_columns { @{ shift->{list_columns} || [] } }
	
	# Method: set_list_columns()
	# Set the list of columns that you want to see in the reults. Note: The list is not checked for valid column names.
	sub set_list_columns { 
		my $self = shift;
		@_ = @{shift()} if ref $_[0] eq 'ARRAY';
		$self->{list_columns} = \@_;
	}
	
	# Method: set_search_hook($coderef)
	# Add a hook to the search routine that is executed like so:
	# my $result = $coderef->($filter)
	# Where $filter is the string given in set_filter(), and result
	# is expected to contain { sql_data => '', args => [] }
	sub set_search_hook
	{
		my ($self, $hook) = @_;
		$self->{search_hook} = $hook;
	}
	
	# Method: search_hook()
	# Returns the current search hook, if any
	sub search_hook { shift->{search_hook} }
	
	# Method: cdbi_class()
	# Return the class name used as a data source for this model.
	# NOTE: This class MUST inherit from AppCore::DBI or implement the AppCore::DBI meta(), field_meta(), get_where_clause(), and get_stringify_sql() methods.
	sub cdbi_class { shift->{cdbi_class} }
	
	# Method: get_complex_filters()
	# In a list context, return a list of complex predefined filters available.
	# In a scalar context, return a hashref of {id => $ref} 
	sub get_complex_filters 
	{ 
		my $self = shift;
		return wantarray ? () : {} if !ref $self;
		
		my $filter_list = $self->{complex_filters};
		return wantarray ? () : {} if !$filter_list;
		return wantarray ? @$filter_list : map {$_->{id} => $_} @$filter_list;
	}
	
	# Method: set_complex_filter($filter_ref)
	# Set the filter to be used - should be a hashref returned from get_complex_filters()
	sub set_complex_filter($filter_ref)
	{
		my $self = shift;
		my $filter_ref = shift;
		
		if(!$filter_ref)
		{
			undef $self->{complex_filter};
			return $filter_ref;
		}
		
		if(!ref $filter_ref || ref $filter_ref ne 'HASH')
		{
			warn $@ = "[WARN] $self: set_complex_filter('$filter_ref'): Argument is not a hashref - ignoring and not changing complex filter.\n";
			return undef;
		}
		
		warn "[WARN] $self: set_complex_filter($filter_ref): \$filter_ref sppears invalid - the {query} attribute appears to be undefined or empty. This may cause problems when compile_list() or get_total_rows() is called!\n"
			if !$filter_ref->{query};
			
		$self->{complex_filter} = $filter_ref;
		return $filter_ref;
	}
	
	# Method: complex_filter()
	# Return the hashref as the complex filter currently in use.
	sub complex_filter { shift->{complex_filter} }
	
	# Method: set_harcoded_filter(%args)
	# Set the list of hardcoded filters, for example:
	# class->set_hardcoded_filter( deleted => 0 )
	# will add the SQL "deleted = 0" to the end of the WHERE clause
	sub set_hardcoded_filter
	{
		my $self = shift;
		my %args = @_;
		
		$self->{hardcoded_filter} = \%args;
	}
	
	# Method: column_search_alises()
	# Return a hasref if set giving the aliases for search string parsing
	sub column_search_alises { shift->{column_search_alises} }
	
	# Method: set_column_search_alises($hashref)
	# Set the column search aliases for parsing the search string when searching.
	# This is useful, for example, when you have a column called primary_category,
	# but you want the user to be able to search by 'category:foobar' or 'cat:foobar', 
	# not just 'primarycategory:foobar'. In this case, you could do:
	# $class->column_search_alises({
	# 	cat => 'primary_category',
	# 	category => 'primary_category'
	# });
	sub set_column_search_alises {
		my $self = shift;
		my $hashref = shift;
		
		die "column_search_alises: Must provide a hasref" if ref $hashref ne 'HASH';
		
		$self->{column_search_alises} = $hashref;
	}
	
	sub is_filtered { shift->{is_filtered} }
	
	sub get_db_name
	{
		my $self = shift;
		my $class = $self->cdbi_class;
		
		my $db_name = $class->meta->{db};
		if(!$db_name)
		{
			my $dsn = $class->db_Main->{Name};
			$dsn =~ /database=([^;]+)/;
			$db_name = $1;
		}
		
		return $db_name;
	}
	
	
	sub get_total_rows
	{
		my $self = shift;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		my $db    = $dbh->quote_identifier($self->get_db_name);
		my $table = $dbh->quote_identifier($class->table);		
		my $pri   = $dbh->quote_identifier($class->primary_column);
		
		my $select_columns = 'SELECT COUNT('.$pri.') as `count`';
		
		
		## Prepare WHERE clause
		my ($extra_tables, $query, $query_args) = $self->create_sql_filter();
		my $where_clause = ' WHERE '.$query;
		
		## Prepare FROM clause
		my $from_tables = ' FROM '.$dbh->quote_identifier($class->table). ($extra_tables && @$extra_tables ?', '.join(',',map {$dbh->quote_identifier($_)} @$extra_tables):'');
		
		## Prepare complete SELECT statement
		my $sql_table = join("\n    ",
			$select_columns,
			$from_tables,
			$where_clause,
		);
		
		#print STDERR "SQL: ".$sql_table."\n". ($query_args ? "Args: ".join(',',map{$dbh->quote($_)} @$query_args)."\n" : "NO ARGS\n");
		
		## Execute the selection and extract count
		my $sth_count = $dbh->prepare($sql_table);
		$sth_count->execute($query_args ? @$query_args : ()); #@args);
		
		return $sth_count->rows ? $sth_count->fetchrow_hashref->{count} : 0;
	}
	
	
	sub compile_list
	{
		my $self = shift;
		my ($start,$length,$debug) = @_;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		# For use in the inner loop to make table monikers unique
		my $moniker_sequence_num = 0;
		
		my $db    = $dbh->quote_identifier($self->get_db_name);
		my $table = $dbh->quote_identifier($class->table);
		my $pri   = $dbh->quote_identifier($class->primary_column);
		
		my $meta = eval '$class->meta' || $self->{meta};
		my $table_list = $self->list_columns || [ map { $_->{name} } $class->columns ];
		
		# If search ranking requested, generate the args needed
		my ($rank_column, $rank_column_args);
		
		my $ranking_enabled = 
			$self->{search_ranking} &&
			length($self->filter) > 0;
		
		if($ranking_enabled)
		{
			($rank_column, $rank_column_args) = $self->create_rank_column(undef,1);
		}
		
		
		## Create the list of columns to select from the database
		my @columns;
		my $got_pri = 0;
		foreach my $col (@$table_list)
		{
# 			if($col eq 'empid')
# 			{
# 				my $link = $class->field_meta($col)->{linked};
# 				#die Dumper eval '$link->can("get_stringify_sql")' ? 1:0;
# 			}
			my $link = $class->field_meta($col)->{linked};
			if($link && eval '$link->can("get_stringify_sql")')
			{
				my $meta = eval '$link->meta';
				#die Dumper $meta if $x->{linked} =~ /Auth/;
				if(!$meta || !$meta->{db} || !$meta->{database})
				{
					my $dsn = $link->db_Main->{Name};
					$dsn =~ /database=([^;]+)/;
					$meta->{db} = $1;
					#die Dumper $meta,$dsn;
				}
				
				my $other_db   = $dbh->quote_identifier($meta->{db} || $meta->{database});
				
				my $table      = $dbh->quote_identifier($link->table);
				my $primary    = $dbh->quote_identifier($link->primary_column);
				my $self_table = $dbh->quote_identifier($class->table);
				my $self_field = $dbh->quote_identifier($col);
				
				my $self_ref  = "$db.$self_table";
				my $other_ref = "$other_db.$table";
				my $moniker   = "";
				if($other_ref eq $self_ref)
				{
					# This is to handle subqueries that query the same table as the outer query.
					# For example, say we're trying to make a subquery for a column called 'parentid' that looks up the
					# name of the parent row in the same table - we've got to make the table monikers unique for the query
					# to process correctly, since its the same table.
					$moniker   = $dbh->quote_identifier($link->table.(++$moniker_sequence_num));
					$other_ref = $moniker;
				}
				
				#Args: get_stringify_sql($lower_case||0,$depth||0,$user_order||0,$tbl_moniker||undef)
				my $concat     = $link->get_stringify_sql(0,0,0,$moniker);
				#die Dumper $concat if $col eq 'parent_articleid';
				#die Dumper $concat;
					
				push @columns, "(SELECT $concat FROM $other_db.$table $moniker WHERE $other_ref.$primary=$self_ref.$self_field) \n".
					"\tAS ".$dbh->quote_identifier($col)."\n";
				
				# Add a $col+'_raw' column (ex: userid_raw) which is just the $col from this table but not stringified
				push @columns, "$self_ref.$self_field \n".
					"\tAS ".$dbh->quote_identifier($col.'_raw')."\n";
			}
			else
			{
				my $cname = $dbh->quote_identifier($col);
				push @columns, "$db.$table.$cname\n";
				$got_pri = 1 if $cname eq $pri;
				#die Dumper $cname if $got_pri;
			}
		}
		push @columns, $pri if !$got_pri;
		
		if($ranking_enabled)
		{
			push @columns, "(\@search_rank := $rank_column)\n".
				"\t AS _search_rank\n";
			push @columns, "ROUND(\@search_rank)\n".
				"\t AS _search_rank_int\n";
		}
		
		my $select_columns = 'SELECT '.join(', ',@columns);
		
		## Prepare LIMIT clause
		$start =~ s/[^\d]//g;
		$start = int($start);
		#$start = 0 if !$start;
		
		$length =~ s/[^\d]//g;
		$length = int($length);
		#$length = 50 if !$length;
		
		my $limit_clause = defined $start && $length ? ' LIMIT '.$start.', '.$length : '';
		
		## Prepare WHERE clause
		my ($extra_tables, $query, $query_args) = $self->create_sql_filter();
		my $where_clause = ' WHERE '.$query;
		
		# Add in ranking data if requested
		if($ranking_enabled)
		{
			# Tack on our injection code to the where clause
			#$where_clause .="\n AND ".$rank_query;
			
			# Tack on the string args from the ranking function to calculate rank values
			#push @$query_args, @$rank_column_args;
			$query_args = [ @$rank_column_args, @$query_args ];
		}
		
		
		## Prepare FROM clause
		my $from_tables = ' FROM '.$db.'.'.$dbh->quote_identifier($class->table).
			($extra_tables && @$extra_tables ? ', '.join(',',map {$dbh->quote_identifier($_)} @$extra_tables):'');
		
		## Integrate advanced filters
		my @adv_sort;
		
		my $adv = $self->{advanced_filters}->{sort};
		if($adv && ref $adv eq 'ARRAY')
		{
			@adv_sort = map { [$_->{column},lc $_->{dir} eq 'up' ? 'DESC' : 'ASC'] } @$adv;
		}
		
		## Prepare ORDER BY clause
		my $orderby_sql = $class->get_orderby_sql(@adv_sort ? \@adv_sort : ($self->sort_column ? {
			'sort' => $self->sort_column    || '',
			'dir'  => $self->sort_direction || '',
		} : undef));
		
		#die "'$orderby_sql'";
		my $sort_clause = $orderby_sql ? 
			" ORDER BY ".($ranking_enabled ? "_search_rank desc, " : '') . $orderby_sql : 
			($ranking_enabled ? "ORDER BY _search_rank desc" : '');
		
		#print STDERR "\$orderby_sql: '$orderby_sql'\n";
		
		
		## Prepare complete SELECT statement
# 		my $sql_table = join("\n    ",
# 			$select_columns,
# 			$from_tables,
# 			$where_clause,
# 			$sort_clause,
# 			$limit_clause
# 		);
		
		my $sql_table = join("\n",
			$select_columns,
			$from_tables,
			$where_clause,
			$sort_clause,
			$limit_clause
		);
		
		#use AppCore::Common;
		#die Dumper \@$query_args;
		#die AppCore::Common::debug_sql($sql_table, @$query_args);# if $debug;
		#print STDERR "SQL: ".$sql_table."\n". ($query_args ? "Args: ".join(',',map{$dbh->quote($_)} @$query_args)."\n" : "NO ARGS\n");
		
		#print STDERR AppCore::Common::get_stack_trace();
		
		#print STDERR "Adv Filter: ".Dumper($self->{advanced_filters});
		## Execute the selection and add it to @list
		my $sth_table = $dbh->prepare($sql_table);
		$sth_table->execute($query_args ? @$query_args : ());
		
		my @list;
		push @list, $_ while $_ = $sth_table->fetchrow_hashref;
		
		return \@list;
		
		
	}
	
	sub load_advanced_filters
	{
		my $self = shift;
		my $value = shift;
		
		die "Advanced filters no longer supported";
	}
	
	sub parse_ssv
	{
		my $text = shift;      # record containing space-separated values
		$text .= ' 2'; # HACK HACK HACK - without this, last word is dropped
		my @new  = ();
		push(@new, $+) while $text =~ m{
			# the first part groups the phrase inside the quotes.
			# see explanation of this pattern in MRE
			"([^\"\\]*(?:\\.[^\"\\]*)*)"\s?
			|  ([^\s]+)\s+?
			| \s+
		}gx;
		push(@new, undef) if substr($text, -1,1) eq ' ';
		return @new;      # list of values that were comma-separated
	}

	sub set_string_parse_exclude
	{
		my $self = shift;
		my @exclude_list = @_;
		my %map = map { lc $_ => 1 } @exclude_list;
		
		my $cdbi_class = $self->cdbi_class;
		my @schema = @{ $cdbi_class->meta->{schema} || []};
		my @acceptable = map { $_->{field} } grep { $_->{field} && !$map{lc $_->{field}} } @schema; 
		
		$self->{string_query_fields} = \@acceptable;
	}
	
	sub set_string_parse_fields
	{
		my $self = shift;
		my @good_list = @_;
		my %map = map { lc $_ => 1 } @good_list;
		
		my $cdbi_class = $self->cdbi_class;
		my @schema = @{ $cdbi_class->meta->{schema} || []};
		my @acceptable = map { $_->{field} } grep { $_->{field} && $map{lc $_->{field}} } @schema; 
		
		$self->{string_query_fields} = \@acceptable;
	}
	
	sub set_string_filters
	{
		my $self = shift;
		my $filter_hash = shift || {};
		$self->{string_query_filters} = $filter_hash;
	}
	
	sub parse_string_query
	{
		my $self = shift;
		my $search_query = shift;
		
		# Not really used right now, but legacy code available commented out, just needs tested
		my $filter_hash = shift || $self->{string_query_filters} || {};
		
		#die Dumper $filter_hash;
		
		return { sql => '1=1', args => [] } if !$search_query;

		my $cdbi_class = $self->cdbi_class;
		
		my @term_words = parse_ssv($search_query);
		my @term_negs  = grep {  /^-/ } @term_words;
		@term_negs     = map { s/^-//g; $_ } @term_negs;
		@term_words    = map { s/^-//g; $_ } @term_words;
		
		my %is_neg     = map { $_ => 1 } @term_negs;
		
		@term_words    = sort { $is_neg{$a} <=> $is_neg{$b} } @term_words;
		
		#print STDERR Dumper(\@term_words, \%is_neg);
		#die Dumper(\@term_words, \%is_neg);
		
		my $DEBUG = 0;
		
		my @search_sql;
		my @search_args;
		
		# NOTE: Special case pre-parsing - not sure how to handle generically
		# Pre-parse for "first/last" termoid and preprocess
		if($cdbi_class->has_field('last') && 
		   $cdbi_class->has_field('first'))
		{
			my @first_last_termoids = grep { /^.*?[\/\\].*?$/ } @term_words;
			@term_words = grep { !/^.*?[\/\\].*?$/ } @term_words;
			foreach my $termoid (@first_last_termoids)
			{
				my ($xa, $type, $xb) = $termoid =~ /^(.*?)([\/\\])(.*?)$/;
				my $sta = $type eq '/' ? 'last' : 'first';
				my $stb = $type eq '/' ? 'first' : 'last';
				push @term_words, $sta.':'.$xa.'*';
				push @term_words, $stb.':'.$xb.'*';
			}
		}
		
		my %col_match_type = (
			#'code' => '=',
			'id'   => '=',
			$cdbi_class->primary_column => '='
		);
		
		my %col_q_cast = (
			#id => q{(CASE WHEN ISNUMERIC(?) THEN CONVERT(int, REPLACE(LTRIM(RTRIM(?)), ',', '.')) ELSE 0 END)},
		);
		
		print STDERR "[Debug] parse_string_query(): Original query: '$search_query'\n" if $DEBUG;
		print STDERR "[Debug] parse_string_query(): Parsed term words: ".join(' & ', map{ "'$_'" } @term_words)."\n" if $DEBUG;
		
		
		my @schema = @{ $cdbi_class->meta->{schema} || []};
		my %col_name_map;
		
		my $aliases = $self->column_search_alises();
		if(ref $aliases eq 'HASH')
		{
			%col_name_map = map { lc $_ => $aliases->{$_} }
				keys %{$aliases || {} };
		}
		
		foreach my $dat (@schema)
		{
			my $field = $dat->{field};
			$col_name_map{$field} = $field;
			
			my $title = lc guess_title($field);
			$title =~ s/#$//g;
			$title =~ s/\s//g;
			$col_name_map{$title} = $field;
			
			my $title2 = lc $dat->{title};
			$title2 =~ s/#$//g;
			$title2 =~ s/\s//g;
			$col_name_map{$title2} = $field;
		}
		
		# Alias 'id' to primary column
		$col_name_map{id} = $cdbi_class->primary_column;
		
		my @string_query_cols = map { $_->{field} } @schema;
		
		# Filter @string_query_cols by $self->{string_query_fields} if defined
		if($self->{string_query_fields})
		{
			my %string_query_fields = map { lc $_ => 1 } @{ $self->{string_query_fields} || [] };
			@string_query_cols = grep { $string_query_fields{ lc $_ } } @string_query_cols;
		}
		
		foreach my $possible_union (@term_words)
		{
			my @union_search_sql;
			my @union_terms = split(/\|/, $possible_union);
			#die Dumper \@union_terms if @union_terms > 1;
			RAW_TERM: foreach my $raw_term (@union_terms)
			{
				# We keep a list of all the IDs we match for this raw_term,
				# then at the end we merge them into @id_list_master
				my @term_id_list;
				
				print STDERR "[Debug] parse_string_query(): \$raw_term: '$raw_term'\n" if $DEBUG;
				my ($search_col, $termoid) = $raw_term =~ /^([\w_]+):\s*(.*)$/;
				
				print STDERR "[Debug] parse_string_query(): \$search_col: '$search_col', \$termoid: '$termoid'\n" if $DEBUG;

				# We dont want to use the user's search term directly in SQL, so we will search first then build a list of IDs and use that in the search clause
				my @value_cols = @string_query_cols;
				
				#my @user_cols = qw/created_by assigned_to/;
				
	# 			my %col_name_map = qw/
	# 				last lastname
	# 				first firstname
	# 				middle --
	# 				display _display_
	# 				name _display_
	# 				status --
	# 				recruiter --
	# 				r --
	# 				code --
	# 				event event
	# 				program programs
	# 				phone phone
	# 				email email
	# 			/;
	# 			$col_name_map{id}        = $master_type eq 'pr' ? 'p.ProspectID' : 's.StudentUID';
	# 			$col_name_map{status}    = $master_type eq 'pr' ? 'p.Status' : 's.ProspectStatus';
	# 			$col_name_map{recruiter} = $master_type eq 'pr' ? 'p.[Recruiters Name]' : 's.RecruiterName';
	# 			$col_name_map{r}         = $col_name_map{recruiter};
	# 			$col_name_map{code}	= $master_type eq 'pr' ? q{(case when p.[User Defined] <> '' then p.[User Defined] else 'Z-NoCode' end)} :
	# 									 q{(case when s.UserDefined    <> '' then s.UserDefined    else 'Z-NoCode' end)};
	# 			$col_name_map{event}     = $master_type eq 'pr' ? 'p.Event' : 's.ProspectEvent';
	# 			$col_name_map{first}     = $master_type eq 'pr' ? 'p.FirstName' : 's.FirstName';
	# 			$col_name_map{last}      = $master_type eq 'pr' ? 'p.LastName' : 's.LastName';
	# 			$col_name_map{middle}    = $master_type eq 'pr' ? 'p.MiddleInitial' : 's.MiddleName';
	# 			$col_name_map{firstname} = $col_name_map{first};
	# 			$col_name_map{lastname}  = $col_name_map{last};
				
				my $negate_flag = $is_neg{$raw_term};
				
				if($search_col)
				{
					$search_col = lc $search_col;
					
					if(defined $col_name_map{$search_col})
					{
						@value_cols = ($col_name_map{$search_col});
						#@user_cols = ();
					}
					elsif($search_col eq 'filter')
					{
						if($filter_hash->{$termoid})
						{
							push @union_search_sql,
								$negate_flag ? 'not ('.$filter_hash->{$termoid}->{sql}.')' : 
									$filter_hash->{$termoid}->{sql};
									
							$filter_hash->{$termoid}->{selected} = 1; # since this is a ref, it should update the UI above
							
							next RAW_TERM;
						}
						else
						{
							die "Invalid filter '$termoid'";
						}
					}
					else
					{
						die "Search field '$search_col' does not exist, ".Dumper(\%col_name_map)."\n";
						$termoid = $raw_term;
					}
				}
				else
				{
					$termoid = $raw_term;
				}
				
				if(($search_col && !$termoid) || (!$search_col && length($termoid) < $MIN_TERMOID_LENGTH))
				{
					warn "Not using termoid '$termoid' - less than $MIN_TERMOID_LENGTH characters (search_col:$search_col)";
					next RAW_TERM;
				}
				
				# Allow wildcard searching
				$termoid =~ s/\*/%/g;
				
				print STDERR "[Debug] parse_string_query():     Parsed fields, \@value_cols =(".join(',',@value_cols).")\n" if $DEBUG;
				#print STDERR "[Debug] parse_string_query():     Parsed fields, \@user_cols  =(".join(',',@user_cols).")\n"  if $DEBUG;

				#die Dumper { value_cols => \@value_cols, user_cols => \@user_cols, search_col => $search_col, term => $termoid };
				if(@value_cols)
				{
					# TODO: Handle special cols
					my %special_cols = (); #map { $_ => 1 } qw/.../;
					my @useful_cols = grep { !$special_cols{$_} } @value_cols;
					my @ids;
					
					print STDERR "[Debug] parse_string_query():     Value Cols, \@useful_cols =(".join(',',@useful_cols).")\n"  if $DEBUG;

					if(@useful_cols)
					{
						my %multicols = (
							#phone	=> [ qw/phone1 phone2 mobilephone/ ],
							#email	=> [ qw/email1 email3/ ],
						);
						
						my %col_specific_termoid = ();
						
						# Store all cols requested before removing the multicols
						my %allcol_map = map { $_ => 1 } @useful_cols;
						
						# Remove multicols from useful because they will be added to stmpt lowr
						@useful_cols = grep { !$multicols{$_} } @useful_cols;
						foreach my $key (keys %multicols)
						{
							# Only add the cols for the multicol if the col $key was requested originally
							push @useful_cols, @{ $multicols{$key} }
								if $allcol_map{$key};
						}
						
						foreach my $key (@useful_cols)
						{
							# Hackish way of specially handling phone numbers
							if($key =~ /phone/)
							{
								my $phone = $termoid;
								$phone =~ s/[^\d]//g;
								$phone =~ s/^1(\d{10})/$1/;
								$phone =~ s/^(\d{3})(\d{3})(\d{4})$/\%$1\%$2\%$3\%/ if length($phone) == 10;
								$phone =~ s/^(\d{3})(\d{4})$/\%$1\%$2\%/ if length($phone) ==  7;
								#$phone = '%'.$phone.'%' if $phone !~ /(\d{10})/;
								#foreach my $col (@{ $multicols{$key} })
								#{
									$col_specific_termoid{$key} = $phone;
								#}
							}
						}
						
						# Build our likes
						#my @likes = map { ($_ eq '_display_' ? "FirstName+' '+MiddleInitial+' '+LastName" : $_).' like ?' } @useful_cols;
						
						my %col_name_subtitutions = %col_name_map;
						
						#$col_name_subtitutions{'_display_'} = 
						#	$master_type eq 'pr' ?  "p.LastName+', '+p.FirstName+' '+p.MiddleInitial" :
						#				"s.LastName+', '+s.FirstName+' '+s.MiddleName";
						
						my @multi_values = split /[,\|]/, $termoid;
						my @multi_stmt;
						my @multi_args;
						
						# NOTE: More testing is needed to see how this multi-value termoid code
						# performs in diverse scenarios
						foreach my $subtermoid (@multi_values)
						{
							
							my @likes = map { $self->get_string_sql_for_field($col_name_subtitutions{$_} ? $col_name_subtitutions{$_} : $_).' '.
									($col_match_type{$_}        ? ($negate_flag ? '!' : '').$col_match_type{$_} :  ($negate_flag ? ' not':'').' like ').' '.
									($col_q_cast{$_}            ? $col_q_cast{$_} : '?') }
									# NOTE: NB In code below, the limiter 2_147_483_647 is max 'int' for MSSQL
									grep { $_ ne 'id' || $subtermoid+0 < 2147483647 } @useful_cols;
							
							# Build the stmt and arg list for the where clause
							my $stmt = '(' . join(($negate_flag ? ' and ' : ' or '), @likes) . ')';
							my @args = map { 
								my $col = $_;
								
								$col eq 'id'                 ? int($subtermoid+0) :
								$col_specific_termoid{$col}  ? $col_specific_termoid{$col} : 
								$col_match_type{$col} eq '=' ? $subtermoid :
									($subtermoid =~ /%/ ? $subtermoid : '%'.$subtermoid.'%') 
									
							} grep { $_ ne 'id' || $subtermoid+0 < 2147483647 }  @useful_cols;
							
							push @multi_stmt, $stmt;
							push @multi_args, @args;
						}
						
						my $stmt = @multi_stmt == 1 ? shift @multi_stmt : '(' . join(' or ', @multi_stmt). ')';
						my @args = @multi_args;
						
						#die Dumper \@useful_cols, \@args;
						#die $stmt."\n\n".Dumper(\@args);
						
						#push @search_sql,  ($negate_flag ? 'not ' : '') . $stmt;
						push @union_search_sql,  $stmt; #($negate_flag ? 'not ' : '') . $stmt;
						push @search_args, @args;
					}
				}
			}
			
			if(@union_search_sql <= 1)
			{
				push @search_sql, @union_search_sql;
			}
			else
			{
				#die Dumper \@union_search_sql, $possible_union;
				push @search_sql, '(' . join(' or ', @union_search_sql). ')';
			}
			
		}

		my $res = {
			sql  => @search_sql ? join(' and ', @search_sql) : ($search_query ? '1=0' : '1=1'),
			args => \@search_args
		};
		
		print STDERR "parse_string_query: query: '$search_query', result: ".Dumper($res)  if $DEBUG;
		#die debug_sql($res->{sql}, @{$res->{args}});
			#if $search_query =~ /\|/;
		
		return $res;
	}
	
	sub get_string_sql_for_field
	{
		my $self = shift;
		my $field = shift;
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		my $field_sql  = $dbh->quote_identifier($field);
		my $field_meta = $class->meta->{field_map}->{lc $field};
		if($field_meta->{linked} && 
			eval($field_meta->{linked}.'->can("get_stringify_sql")'))
		{
			#print STDERR "Debug: get_orderby_sql: field: '$field' ->linked:".$field_meta->{linked}.", get_stringify_sql on linked: ".$field_meta->{linked}->get_stringify_sql."\n";
			
			my $concat = $field_meta->{linked}->get_stringify_sql();
				
			my $linked_meta = eval '$field_meta->{linked}->meta';

			if(!$linked_meta || !$linked_meta->{db} || !$linked_meta->{database})
			{
				my $dsn = $field_meta->{linked}->db_Main->{Name};
				$dsn =~ /database=([^;]+)/;
				$linked_meta->{db} = $1;
			}
			
			my $other_db   = $dbh->quote_identifier($linked_meta->{db} || $linked_meta->{database});
			
			my $table      = $dbh->quote_identifier($field_meta->{linked}->table);
			my $primary    = $dbh->quote_identifier($field_meta->{linked}->primary_column);
			my $self_field = $dbh->quote_identifier($field_meta->{field});
			
			my $db = $class->meta->{db} || $class->meta->{database};
			if(!$db)
			{
				my $dsn = $dbh->{Name};
				$dsn =~ /database=([^;]+)/;
				$db = $1;
				#die Dumper $db,$dsn;
			}
			$db = $dbh->quote_identifier($db);
			
			my $self_table = $dbh->quote_identifier($class->table);
			
			$field_sql = "IFNULL((SELECT $concat FROM $other_db.$table WHERE $other_db.$table.$primary=$db.$self_table.$self_field LIMIT 1),'')";
		}
		else
		{
			#print STDERR "Debug: field: '$field', linked: $field_meta->{linked}, \$@: '$@'\n";
		}
		
		return $field_sql;
	}
	
# 	sub _get_rank_case
# 	{
# 		my ($self, $column_name, $non_wild_string, $wild_string) = @);
# 		
# 		my $dbh = $self->cdbi_class->db_Main;
# 		
# 		# Added protection for quote()
# 		$non_wild_string =~ s/[^[:ascii:]]//g;
# 		$wild_string     =~ s/[^[:ascii:]]//g;
# 		
# 		my $quoted_column  = $dbh->quote_identifier($column_name);
# 		my $quoted_nonwild = $dbh->quote($non_wild_string);
# 		my $quoted_wild    = $dbh->quote($wild_string);
# 		
# 		return qq{
# 		(
# 			case
# 			when lower($quoted_column) like concat('%', lower($quoted_nonwild), '%') then
# 				round ((1-abs((\@last_len:= length(last)) - (\@string_len := length($quoted_nonwild))) / greatest(\@last_len, \@string_len)) * 100)
# 			when lower($quoted_column) like concat('%', lower($quoted_wild), '%') then
# 				round ((1-abs((\@last_len:= length(last)) - (\@string_len := length(replace($quoted_wild,'%','')))) / greatest(\@last_len, \@string_len)) * .5 * 100)
# 			else
# 				0
# 			end
# 		)
# 		};
# 	}
	
	sub enable_search_ranking
	{
		my $self = shift;
		
		my $flag = shift || 0;
		
		$self->{search_ranking} = $flag;
		
		
		# NOTE: MySQL will not let us give a 'delimiter' on the wire like this via a client,
		# so we can't predefine the function.
		# I rewrote the function below into an SQL CASE statement, accessed via _get_rank_case(), above,
		# however, I have concerns about SQL injection even with the use of quote().
		# Instead, I've opted to load it via bin/flush_db.pl from bin/text_match_function.sql.
		# Therefore, we can just always "assume" that match_ratio() exists as a function
		
# 		if($flag)
# 		{
# 			my $dbh = $self->cdbi_class->db_Main;
# 			
# 			my $sql_match_function = 'match_ratio';
# 			
# 			# Add our function to rank results if needed
# 			my $sth_count = $dbh->prepare_cached(q{
# 				SELECT COUNT(1) 
# 				FROM information_schema.ROUTINES as info
# 				WHERE info.ROUTINE_SCHEMA = DATABASE() AND info.ROUTINE_TYPE = 'FUNCTION' AND info.ROUTINE_NAME = ?
# 			});
# 			
# 			$sth_count->execute($sql_match_function);
# 			
# 			if(!$sth_count->fetchrow)
# 			{
# 				$dbh->do(q{
# 				   
# 					DELIMITER //
# 
# 					DROP FUNCTION  IF EXISTS `match_ratio` //
# 					
# 					CREATE FUNCTION `match_ratio` ( s1 text, s2 text, s3 text ) RETURNS int(11)
# 						DETERMINISTIC
# 					BEGIN 
# 						DECLARE s1_len, s2_len, s3_len, max_len INT; 
# 						DECLARE s3_tmp text;
# 								
# 						SET s1_len = LENGTH(s1), 
# 							s2_len = LENGTH(s2);
# 						IF s1_len > s2_len THEN  
# 							SET max_len = s1_len;  
# 						ELSE  
# 							SET max_len = s2_len;  
# 						END IF; 
# 					
# 						if lower(s1) like concat('%',lower(s2),'%') then
# 							return round((1 - (abs(s1_len - s2_len) / max_len)) * 100);
# 						else
# 							set s3_tmp = replace(s3, '%', '');
# 							set s3_len = length(s3_tmp);
# 							
# 							
# 							IF s1_len > s3_len THEN  
# 								SET max_len = s1_len;  
# 							ELSE  
# 								SET max_len = s3_len;  
# 							END IF; 
# 							
# 							if lower(s1) like concat('%',lower(s3),'%') then
# 								/*round(abs(s1_len - s3len) / max_len * .5 * 100);*/
# 								return round((1 - (abs(s1_len - s3_len) / max_len)) * .5 * 100);
# 							else
# 							
# 								return 0;
# 							end if;
# 						end if;
# 					
# 					END //
# 					DELIMITER
# 				});
# 			}
# 
# 		}
		
	}
	
	sub create_rank_column
	{
		my $self = shift;
		my $filter = shift || $self->filter;
		my $dont_parse_string = shift || 0;
		
		#print STDERR "$self: \$filter='$filter'\n";
		
		my $class = $self->cdbi_class;
		
		my $dbh = $class->db_Main;
		
		my $db_quoted    = $dbh->quote_identifier($self->get_db_name);
		my $table_quoted = $dbh->quote_identifier($class->table);
		
		my $rank_sql;
		my @args;
		
		{
			my $filter_wild = lc($filter);
			#$filter_wild =~ s/\s+/%/g;
			
			$filter_wild =~ s/\s+/ /g;	 # collapse spaces
			my $filter_nonwild = $filter_wild;
			
			$filter_wild =~ s/[^\da-z]/ /g;	 # remove anything not a digit or a letter
			$filter_wild =~ s/(.)/$1%/g;	 # insert '%' between every character
			$filter_wild =~ s/%\s*%/%/g;	 # collapse '% %' into '%'
			$filter_wild = '%'.$filter_wild; # '%' implicitly is added to the end by the regex 2 lines above

			# Get the list of columns to use in our ratio
			my @fmt = $class->can('stringify_fmt') ? $class->stringify_fmt : ();
			@fmt = ('#'.($class->meta->{first_string} || $class->primary_column)) if !@fmt;
			@fmt = grep { /^#/ } grep { !/\./ } @fmt;
			s/^#//g foreach @fmt;
			
			# Call match_ratio() to match the filter against each column in the stringify_fmt()
			my @ratio_list;
			@ratio_list = map { 
				push @args, $filter_nonwild, $filter_wild;
				
				'match_ratio(' . $dbh->quote_identifier($_) .', ?, ?)'
			} @fmt;
			
			# Add another 'column' for the ratio against the entire unified stringify_fmt() value
			my $text = $class->get_stringify_sql(1); # 1 = lower case the fields
			
			push @args, $filter_nonwild, $filter_wild;
			
			push @ratio_list, qq{
				match_ratio($text, ?, ?)
			};
			
			# Combine them into an average match ratio as a single SQL statement,
			# suitable for use like "select $rank_sql as `ranking` from ... where ... and $clause"
			# (using the $clause and @args created above to inject the filter strings)
			
			my $ratio_len = scalar @ratio_list;
			
			$rank_sql = "((\n\t"
				.join(" + \n\t", @ratio_list)
				.") / $ratio_len)";
			
# 			my $string_clause = qq{(($text like ?) and ($text <> ""))};
# 			
# 			
# 			#die Dumper(\@args). $string_clause;
# 			#$dont_parse_string
# 			
# 			if($dont_parse_string)
# 			{
# 				$clause = $string_clause;
# 			}
# 			else
# 			{
# 				my $sql_data = $self->parse_string_query($filter);
# 				
# 				$clause = '(' . $string_clause . ' or '. $sql_data->{sql} . ')';
# 				push @args, @{$sql_data->{args} || []};
# 			}
# 			
# 			if($self->{search_hook})
# 			{
# 				my $sql_data = $self->{search_hook}->($filter);
# 				
# 				$clause = '(' . $clause . ' or '. $sql_data->{sql} . ')';
# 				push @args, @{$sql_data->{args} || []};
# 			}
			
			
		}
		
		#print STDERR "$self: clause='$clause', args=".join(',',@args)."\n";
		
		return ($rank_sql, \@args);
	}
	
	sub create_sql_filter
	{
		my $self = shift;
		my $filter = shift || $self->filter;
		my $dont_parse_string = shift || 0;
		
		#print STDERR "$self: \$filter='$filter'\n";
		
		my $class = $self->cdbi_class;
		
		my $dbh = $class->db_Main;
		
		my $db_quoted    = $dbh->quote_identifier($self->get_db_name);
		my $table_quoted = $dbh->quote_identifier($class->table);
		
		my $clause;
		my @args;
		my @tables;
		
		my $searching_flag = 0;
		#die AppCore::Common::debug_sql($clause,@args);
		
		# Added 4/4/14 - Josiah
		# Enable searching by stringified value.
		# E.g. if we have an object that string format is ('#first', ' ', '#last'),
		# and user searches for "John Smith" - the previous search code wont find it, because John Smith isn't in any one column -
		# it's in two columns.
		{
			my $text = $class->get_stringify_sql(1); # 1 = lower case the fields
			
			my $string_clause = qq{(($text like ?) and ($text <> ""))};
			
			my $filter_wild = lc($filter);
			#$filter_wild =~ s/\s+/%/g;
			
			$filter_wild =~ s/\s+/ /g;	# collapse spaces
			$filter_wild =~ s/[^\da-z]/ /g;	# remove anything not a digit or a letter
			$filter_wild =~ s/(.)/$1%/g;	# insert '%' between every character
			$filter_wild =~ s/%\s*%/%/g;	# collapse '% %' into '%'
			$filter_wild = '%'.$filter_wild;
			
			push @args, ($filter_wild);
			
			#die Dumper(\@args). $string_clause;
			#die AppCore::Common::debug_sql($string_clause, @args);
			#$dont_parse_string
			
			if($dont_parse_string)
			{
				$clause = $string_clause;
			}
			else
			{
				my $sql_data = $self->parse_string_query($filter);
				
				$clause = '(' . $string_clause . ' or '. $sql_data->{sql} . ')';
				push @args, @{$sql_data->{args} || []};
			}
			
			if($self->{search_hook})
			{
				my $sql_data = $self->{search_hook}->($filter);
				
				$clause = '(' . $clause . ' or '. $sql_data->{sql} . ')';
				push @args, @{$sql_data->{args} || []};
			}
			
			# Used in SimpleListView.pm
			$self->{is_filtered} = 1 if $filter;
		}
		
		# Support an optional named hook for subclassees
		if($class->can('get_list_clause'))
		{
			my $cl = $class->get_list_clause();
			if($cl)
			{
				$clause .= " and ($cl)";
			}
		}
		
		# Tack on the complex filter to the end
		my $filter = $self->complex_filter();
		if($filter && ($filter->{query} || $filter->{sql}))
		{
			$clause .= ' and ('.($filter->{query} || $filter->{sql}).')';
			push @args, @{ $filter->{args} || [] };
		}
		
		# Add on the hardcoded filter
		my $hard_filter = $self->get_hardcoded_filter_sql();
		if($hard_filter)
		{
			$clause .= ' and ('.$hard_filter->{sql}.')';
			push @args, @{ $hard_filter->{args} || [] };
		}
		
		#die Dumper $hard_filter;
		
		#print STDERR "$self: clause='$clause', args=".join(',',@args)."\n";
		
		#die AppCore::Common::debug_sql($clause, @args);
		
		return (\@tables, $clause, \@args);
	}
	
	sub get_hardcoded_filter_sql
	{
		my $self = shift;
		my $hard = $self->{hardcoded_filter};
		
		#die Dumper $hard;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		my @sql;
		my @args;
		foreach my $col (keys %$hard)
		{
			# Just a small attempt to avoid SQL injection
			next if !$class->has_field($col);
			
			push @sql, $dbh->quote_identifier($col).' = ? ';
			push @args, $hard->{$col};
		}
		
		return undef
			if !@sql;
		
		my $ret = {
			sql  => join(' and ', @sql),
			args => \@args,
		};
		
		return $ret;
	}
	
	sub compile_available_filter_values
	{
		my $self = shift;
		my $col = shift;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		# For use in the inner loop to make table monikers unique
		my $moniker_sequence_num = 0;
		
		my $db    = $dbh->quote_identifier($self->get_db_name);
		my $table = $dbh->quote_identifier($class->table);
		my $pri   = $dbh->quote_identifier($class->primary_column);
		
		my $meta = eval '$class->meta' || $self->{meta};
		my $table_list = $self->list_columns || [ map { $_->{name} } $class->columns ];
			
		## Create the list of columns to select from the database
		my @columns;
		
		my $fm =  $class->field_meta($col);
		my $link = $fm->{linked};
		my $linked_table = 0;
		my $linked_clause = 0;
		if($link && eval '$link->can("get_stringify_sql")')
		{
			my $meta = eval '$link->meta';
			#die Dumper $meta if $x->{linked} =~ /Auth/;
			if(!$meta || !$meta->{db} || !$meta->{database})
			{
				my $dsn = $link->db_Main->{Name};
				$dsn =~ /database=([^;]+)/;
				$meta->{db} = $1;
				#die Dumper $meta,$dsn;
			}
			
			my $other_db   = $dbh->quote_identifier($meta->{db} || $meta->{database});
			
			my $table      = $dbh->quote_identifier($link->table);
			my $primary    = $dbh->quote_identifier($link->primary_column);
			my $self_table = $dbh->quote_identifier($class->table);
			my $self_field = $dbh->quote_identifier($col);
			
			my $link_clause = $fm->{link_clause} ? $fm->{link_clause} : '1';
			
			my $self_ref  = "$db.$self_table";
			my $other_ref = "$other_db.$table";
			my $moniker   = "";
			if($other_ref eq $self_ref)
			{
				# This is to handle subqueries that query the same table as the outer query.
				# For example, say we're trying to make a subquery for a column called 'parentid' that looks up the
				# name of the parent row in the same table - we've got to make the table monikers unique for the query
				# to process correctly, since its the same table.
				$moniker   = $dbh->quote_identifier($link->table.(++$moniker_sequence_num));
				$other_ref = $moniker;
			}
			
			#Args: get_stringify_sql($lower_case||0,$depth||0,$user_order||0,$tbl_moniker||undef)
			my $concat     = $link->get_stringify_sql(0,0,0,$moniker);
			#die Dumper $concat if $col eq 'empid';
			#die Dumper $concat;
				
			#push @columns, "DISTINCT (SELECT $concat FROM $other_db.$table $moniker WHERE $other_ref.$primary=$self_ref.$self_field AND $link_clause) AS ".$dbh->quote_identifier($col);
			$linked_table = "$other_db.$table $moniker";
			$linked_clause = "$other_ref.$primary=$self_ref.$self_field AND $link_clause"; 
			push @columns, "DISTINCT $concat AS ".$dbh->quote_identifier($col);
		}
		else
		{
			my $cname = $dbh->quote_identifier($col);
			push @columns, "DISTINCT $db.$table.$cname";
			#die Dumper $cname if $got_pri;
		}
		
		my $cname = $dbh->quote_identifier($col);
		push @columns, "COUNT($db.$table.$cname) as COUNT";
		
		my $select_columns = 'SELECT '.join(', ',@columns);
		
		## Prepare WHERE clause
		my ($extra_tables, $query, $query_args) = $self->create_sql_filter(undef,1);
		my $where_clause = ' WHERE '.$query.($linked_clause?" AND $linked_clause":'');
		
		## Prepare FROM clause
		my $from_tables = ' FROM '.$dbh->quote_identifier($class->table).($linked_table?", $linked_table":'').($extra_tables && @$extra_tables ?', '.join(',',map {$dbh->quote_identifier($_)} @$extra_tables):'');
		
		
		## Prepare complete SELECT statement
# 		my $sql_table = join("\n    ",
# 			$select_columns,
# 			$from_tables,
# 			$where_clause,
# 		);

		my $sql_table = join(" ",
			$select_columns,
			$from_tables,
			($linked_clause ? "WHERE $linked_clause": ''),
			"GROUP BY $cname ORDER BY COUNT DESC LIMIT 0, 25"
			#$where_clause,
		);
		
# 		if($col eq 'partid')
# 		{
			#print STDERR "Filter Values SQL for '$col': ".$sql_table."\n". ($query_args ? "Args: ".join(',',map{$dbh->quote($_)} @$query_args)."\n" : "NO ARGS\n");
			
			## Execute the selection and add it to @list
			my $sth_table = $dbh->prepare($sql_table);
			$sth_table->execute(); #$query_args ? @$query_args : ());
			
			my @list;
			push @list, $_->{$col} while $_ = $sth_table->fetchrow_hashref;
			
			#use Data::Dumper;
			#print STDERR Dumper \@list,$query_args;
			
			if($fm->{type} =~ /(int|float|double)/i && !$fm->{linked})
			{
				@list = sort { $a <=> $b } @list;
			}
			else
			{
				@list = sort @list;
			}
		
			return \@list;
# 		}
# 		else
# 		{
# 			return [];
# 		}
		
		
	}
};
1;
