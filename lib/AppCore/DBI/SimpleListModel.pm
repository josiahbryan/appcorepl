use strict;


# Package: AppCore::DBI::SimpleListModel
# Simple List Modeling based on AppCore::DBI-derived classes.
# Really just designed to be subclassed rather than used directly.
package AppCore::DBI::SimpleListModel;
{
	use strict;
	use Data::Dumper;
	
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
	sub list_columns { undef }
	
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
	
	# Method: get_hardcoded_filter()
	# Return a list of colname=>value pairs to be "hardcoded" in the SQL query.
	# Subclass to return a value, or use set_harcoded_filter()
	sub get_hardcoded_filter { return %{ shift->{hardcoded_filter} || {} } }
	
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
	
	# Method: parent_recordid()
	# Return the parent recordid to be used in the current query e.g. a list of inv transactions for a parent record
	sub parent_recordid { }
	
	# Method: parent_class()
	sub parent_class    { }
	
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
		my ($start,$length) = @_;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		# For use in the inner loop to make table monkiers unique
		my $monkier_sequence_num = 0;
		
		my $db    = $dbh->quote_identifier($self->get_db_name);
		my $table = $dbh->quote_identifier($class->table);
		my $pri   = $dbh->quote_identifier($class->primary_column);
		
		my $meta = eval '$class->meta' || $self->{meta};
		my $table_list = $self->list_columns || [ map { $_->{name} } $class->columns ];
			
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
				my $concat     = $link->get_stringify_sql;
				#die Dumper $concat if $col eq 'empid';
				#die Dumper $concat;
					
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
				my $monkier   = "";
				if($other_ref eq $self_ref)
				{
					# This is to handle subqueries that query the same table as the outer query.
					# For example, say we're trying to make a subquery for a column called 'parentid' that looks up the
					# name of the parent row in the same table - we've got to make the table monkiers unique for the query
					# to process correctly, since its the same table.
					$monkier   = $dbh->quote_identifier($link->table.(++$monkier_sequence_num));
					$other_ref = $monkier;
				}
					
				push @columns, "(SELECT $concat FROM $other_db.$table $monkier WHERE $other_ref.$primary=$self_ref.$self_field) \n\tAS ".$dbh->quote_identifier($col)."\n";
				
				# Add a $col+'_raw' column (ex: userid_raw) which is just the $col from this table but not stringified
				push @columns, "$self_ref.$self_field \n\tAS ".$dbh->quote_identifier($col.'_raw')."\n";
			}
			else
			{
				my $cname = $dbh->quote_identifier($col);
				push @columns, "$db.$table.$cname";
				$got_pri = 1 if $cname eq $pri;
				#die Dumper $cname if $got_pri;
			}
		}
		push @columns, $pri if !$got_pri;
		
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
		my $sort_clause = $orderby_sql ? " \nORDER BY ".$orderby_sql : '';
		
		
		## Prepare complete SELECT statement
# 		my $sql_table = join("\n    ",
# 			$select_columns,
# 			$from_tables,
# 			$where_clause,
# 			$sort_clause,
# 			$limit_clause
# 		);
		
		my $sql_table = join(" ",
			$select_columns,
			$from_tables,
			$where_clause,
			$sort_clause,
			$limit_clause
		);
		
		#use AppCore::Common;
		#die AppCore::Common::debug_sql($sql_table, @$query_args);
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
		$self->{advanced_filters} = $value;
	}
	
	sub enable_advanced_filters_bookmarks
	{
		my $self = shift;
		my $table_key = shift || $self->cdbi_class;
		my $class = shift || 'AppCore::DBI::SimpleListModel::AdvancedFilterBookmark';
		# the table if it doesnt exist. Columns are (lineid int primary key, table_cookie varchar(255), bookmark_name varchar(255), userid int, is_system smallint(1), timestamp timestamp, query text)
		eval 'use '.$class;
		die "Error loading advanced filters bookmark CDBI class '$class': $@" if $@;
		$self->{advanced_filters_bookmarks_cdbi} = $class;
		$self->{advanced_filters_bookmarks_table_key} = $table_key
	}
	
	sub validate_advanced_filter_bookmark
	{
		my $self = shift;
		my $id = shift;
		my $cdbi = $self->{advanced_filters_bookmarks_cdbi};
		my $table_key = $self->{advanced_filters_bookmarks_table_key};
		if(!$cdbi || !$table_key)
		{
			$@ = "Call enable_advanced_filters_bookmarks() first on the model to enable the bookmarking feature";
			warn $@;
			return [];
		}
		
		my $ref = $cdbi->by_field(table_key => $table_key, lineid => $id);
		$ref = $cdbi->by_field(table_key => $table_key, name => $id) if !$ref;
		
		#print STDERR AppCore::Common::called_from()."Debug: validate_advanced_filter_bookmark($id): ref='$ref'\n";
		
		return $ref;
	}
	
	sub get_advanced_filters_bookmarks
	{
		my $self = shift;
		my $system_flag = shift || undef;
		
		my $cdbi = $self->{advanced_filters_bookmarks_cdbi};
		my $table_key = $self->{advanced_filters_bookmarks_table_key};
		if(!$cdbi || !$table_key)
		{
			$@ = "Call enable_advanced_filters_bookmarks() first on the model to enable the bookmarking feature";
			AppCore::Common::print_stack_trace();
			warn $@;
			return ();
		}
		
		return defined $system_flag ? 
			$cdbi->search(table_key => $table_key, is_system => $system_flag ? 1:0) :
			$cdbi->search(table_key => $table_key);
	}
	
	sub add_advanced_filters_bookmark
	{
		my $self = shift;
		
		# Allow users to pass in an arrayref of filters to add, say, for bulk syststem loading
		if(@_ == 1 && ref($_[0]) eq 'ARRAY')
		{
			my @output;
			push @output, $self->add_advanced_filters_bookmark(@{$_}) foreach @{$_[0]};
			return @output;
		}
		
		#use Data::Dumper;
		#print STDERR Dumper \@_;
		
		my $filter_name = shift || 'Saved Query # '.time();
		my $query_blob = shift;
		my $user = shift || AppCore::Common->context->current_user;
	
		my $cdbi = $self->{advanced_filters_bookmarks_cdbi};
		my $table_key = $self->{advanced_filters_bookmarks_table_key};
		if(!$cdbi || !$table_key)
		{
			$@ = "Call enable_advanced_filters_bookmarks() first on the model to enable the bookmarking feature";
			warn $@;
			return undef;
		}
		
		return $cdbi->create({table_key=>$table_key, userid=>$user, query=>$query_blob, name => $filter_name});
	}
	
	sub create_sql_filter
	{
		my $self = shift;
		my $filter = shift || $self->filter;
		my $dont_process_advanced = shift || 0;
		
		#print STDERR "$self: \$filter='$filter'\n";
		
		my $class = $self->cdbi_class;
		
		my $dbh = $class->db_Main;
		
		my $db_quoted    = $dbh->quote_identifier($self->get_db_name);
		my $table_quoted = $dbh->quote_identifier($class->table);
		
		
		# Hard filter is specified by the using class
		my %hard_args = $self->get_hardcoded_filter;
		
		my @clause;
		my @args;
		my @tables;
		
		
		my $searching_flag = 0;
		my $filtercols = eval '$class->meta->{filter_list}' || $self->{filter_list} || $self->{table_list} || [$class->columns];
		
		my $advanced_filters = $dont_process_advanced ? undef : $self->{advanced_filters}->{filters};
		print STDERR "Advanced Filters: ($dont_process_advanced): ".Dumper($advanced_filters);
		
		if(ref $filtercols eq 'ARRAY')
		{
			my $val = $filter;
			#print STDERR "$self: create_sql_filter: mark2: val='$val'\n";
			
			$searching_flag = 1 if $val;
				
				
			# Now build the actual search clause for the sql
			foreach my $col (@$filtercols)
			{
				my $adv = $advanced_filters ? $advanced_filters->{$col} : undef;
				#$adv = {search=>$val} if $advanced_filters && !$adv && $val;
				
				#print STDERR "$self: create_sql_filter: mark1: col:'$col', val='$val', advanced_filters:$advanced_filters, adv:".Dumper($adv);
				next if !$adv && $advanced_filters;
				
				my @value_list = $adv ? @{ $adv->{filters} || [] } : ();
				
				if(@value_list)
				{
					#print STDERR "Debug: $col: Got value list: ".Dumper(\@value_list);
					my $col_meta = $class->field_meta($col);
					if(my $link = $col_meta->{linked})
					{
						eval 'use '.$link;
						#print STDERR " * Linked col: loading class $link\n";
						warn $@ if $@;
					}
								
					my @value_set = ();
					foreach my $val (@value_list)
					{
						#print STDERR " * Processing value '$val'\n";
						eval
						{
					
							if(my $link = $col_meta->{linked})
							{
								#die Dumper $link if $col =~ /partid/;
								my $val = $link->validate_string($val);
								#die Dumper \@list, $val if $col =~ /partid/;
								#if($res->{id})
								
								#print STDERR "mark1\n";
								if($val)
								{
									#print STDERR " * Linked col: loading class $link\n";
									push @value_set, $val;
								}	
							}
							else
							{
								if($col_meta->{type} =~ /^(int|float)/ && $val !~ /^[+-](\d+\.\d+|\d+\.|\.\d+)$/)
								{
									#print STDERR "Debug Warning: Skipping clause on column '$col' because $col is a number and '$val' doesn't look like a number\n";
								}
								else
								{
									push @value_set, $val;
								}
								
								#print STDERR Dumper $inq, $cl, \@args2;
								
							}
						};
						
						if($@)
						{
							die "$@ Died while processing filter column '$col' on class ".(ref $class ? ref $class : $class);
						}
					}
					
					
					push @clause, "($db_quoted.$table_quoted.".$dbh->quote_identifier($col)." in (".join(',',map { $dbh->quote($_) } @value_set)."))";
				}
				else
				{
					my $search_string = $val;
					if( $adv && $adv->{search} )
					{
						$searching_flag = 1;
						$search_string = $adv->{search} ;
					}
					
					#print STDERR "$self: create_sql_filter: mark3: col:'$col', val='$search_string'\n";
					
					eval
					{
				
						my $col_meta = $class->field_meta($col);
						if(my $link = $col_meta->{linked})
						{
							#die Dumper $link if $col =~ /partid/;
							eval 'use '.$link;
							
							my @list = $link->validate_string($search_string,undef,1);
							
							print STDERR "SimpleListModel: val:'$search_string', col: $col: validating string for link $link, res:[@list]\n";
							
							
							#die Dumper \@list, $search_string if $col =~ /partid/;
							#if($res->{id})
							
							#print STDERR "mark1\n";
							if(@list)
							{
								push @clause, "($db_quoted.$table_quoted.".$dbh->quote_identifier($col)." in (".join(',',@list)."))";
							}	
						}
						else
						{
							if($col_meta->{type} =~ /^(int|float)/ && $search_string !~ /^[+-]?(\d+|\d+\.\d+|\d+\.|\.\d+)$/)
							{
								#print STDERR "Debug Warning: Skipping clause on column '$col' because $col is a number and '$search_string' doesn't look like a number\n";
							}
							elsif($col_meta->{type} =~ /^(date)/ && $search_string !~ /^\d+-\d+-\d+$/)
							{
								#print STDERR "Debug Warning: Skipping clause on column '$col' because $col is a number and '$search_string' doesn't look like a number\n";
							}
							else
							{
								#print STDERR "mark3\n";
								my $inq = {$col=>$search_string};
								my ($tables,$cl,@args2) = $class->can('get_where_clause')     ? $class->get_where_clause($inq,2) : 
											  $class->can('compose_where_clause') ? $class->compose_where_clause($inq,$class->_legacy_typehash,undef,2) :
											  (undef,"$db_quoted.$table_quoted.".$dbh->quote_identifier($col).'=?',$search_string);	
								next if $cl eq '1';
								
								push @clause, "($cl)";
								push @args, @args2;
								push @tables, $tables if $tables && $tables ne '';
								#print STDERR "create_sql_filter('$search_string') [DEBUG] col='$col': \$cl='$cl'\n";
							}
							
							#print STDERR Dumper $inq, $cl, \@args2;
							
						}
					};
					
					if($@)
					{
						die "$@ Died while processing filter column '$col' on class ".(ref $class ? ref $class : $class);
					}
				}
			}
		
			
		}
		$self->{is_filtered} = $searching_flag;
		
		my $clause = @clause ? '(' . join (($advanced_filters ? ' and ' : ' or '), @clause) . ')' : '1';
		
		#print STDERR "\$clause: $clause\n";
		
		#die AppCore::Common::debug_sql($clause,@args);
		
		# Added 4/4/14 - Josiah
		# Enable searching by stringified value.
		# E.g. if we have an object that string format is ('#first', ' ', '#last'),
		# and user searches for "John Smith" - the above search code wont find it, because John Smith isn't in any one column -
		# it's in two columns.
		#
		# Note - 12/4/14 - Josiah
		# This may now be redudant since I revised the legazy clause in AppCore::DBI::validate_string
		# to multi-match with the stringify sql - in essance, doing what this does below, only for individual linked columns
		# However, I'll leave this in unless singificant server impact is shown/reported.
		{
			my $text = $class->get_stringify_sql;
			
			my $string_clause = qq{(($text like ?) and ($text <> ""))};
			push @args, ('%'.$filter.'%');
			
			$clause = @clause ? "($clause or $string_clause)" : $string_clause;
		}
		
		@clause = ();
		
		
		#### If screen_list() is being used to generate a sub-list for a parent class (e.g. think list of transactions for an inventory item),
		# then we must find the column that links to the parent class given in parent_class(), and put that column name into %hard_args
		# with the value that is already in hardargs for parent_recordid.
		my $det_for = $self->parent_class;
			
		if($det_for)
		{

			my $linked_field = $self->{detail_field};
			if(!$linked_field)
			{
				my @fields = @{$class->meta->{schema} || []};
				foreach my $field (@fields)
				{
					if($field->{linked} eq $det_for)
					{
						$linked_field = $field;
						last;	
					}
				}
			}
			
			if(!$linked_field)
			{
				die "Cannot find field linked to parent class $det_for";
			}
			
			my $parent_recordid = $self->parent_recordid;
			if(!defined $parent_recordid)
			{
				die "Parent class $det_for specified, but no parent_recordid given to screen_list()";
			}
			
			#delete $defaults->{parent_recordid};
			#$defaults->{ref $linked_field ? $linked_field->{field} : $linked_field} = $parent_recordid;
			my $key = ref $linked_field ? $linked_field->{field} : $linked_field;
			$hard_args{$key} = $parent_recordid;
			#print STDERR "Debug: \$hard_args{$key} = '$parent_recordid'\n";
	
			
			#die Dumper \%hard_args;
			
			#die Dumper \%hard_args;
			
		}
		
		## Build the "hard args" clause (passed by the "using" class as absolutly must match)
		foreach my $col (keys %hard_args)
		{
			my $data = $hard_args{$col};
			
			#print STDERR "col=$col, data=$data\n";
			if(ref $data eq 'ARRAY')
			{
				my ($tables,$cl,@args2) = @$data;
				push @clause, "($cl)";
				push @args, @args2;
				push @tables, $tables if $tables && $tables ne '';
			}
			else
			{
				my $col_meta = $class->field_meta($col);
				if(!$col_meta)
				{
					die "Cannot find column meta for $col ($hard_args{$col}) in class $class";
				}
				
				if(my $link = $col_meta->{linked})
				{
					my @list = $link->validate_string($hard_args{$col},undef,1);
					#if($res->{id})
					if(@list)
					{
						push @clause, "($db_quoted.$table_quoted.".$dbh->quote_identifier($col)." in (".join(',',@list)."))";
						#push @args, $res; #->{id};
					}	
				}
				else
				{	
					if($col_meta->{type} =~ /^(int|float)/ && $data !~ /^[+-]?(\d+\.\d+|\d+\.?|\.\d+)$/)
					{
						print STDERR "Debug Warning: Skipping clause on column '$col' because $col is a number and '$hard_args{$col}' doesn't look like a number\n";
					}
					else
					{
						#use Data::Dumper;
					
						my $inq = {$col=>$data};
						#print STDERR Dumper $inq;
						my ($tables,$cl,@args2) = $class->can('get_where_clause')     ? $class->get_where_clause($inq,2) : 
									  $class->can('compose_where_clause') ? $class->compose_where_clause($inq,$class->_legacy_typehash,undef,2) :
									  (undef,"$db_quoted.$table_quoted.".$dbh->quote_identifier($col).'=?',$hard_args{$col});	
						#print STDERR Dumper $tables, $cl, \@args2;
						push @clause, "($cl)";
						push @args, @args2;
						push @tables, $tables if $tables && $tables ne '';
					}
				}
			}
		}	
		
		$clause .= @clause ? ' and ' . join (' and ', @clause) : '';
		if($class->can('get_list_clause'))
		{
			my $cl = $class->get_list_clause();
			if($cl)
			{
				$clause .= " and ($cl)";
			}
		}
		
		my $adv_filter = $self->complex_filter();
		if($adv_filter && $adv_filter->{query})
		{
			$clause .= ' and ('.$adv_filter->{query}.')';
		}
		
		#print STDERR "$self: clause='$clause', args=".join(',',@args)."\n";
		
		return (\@tables, $clause, \@args);
	}
	
	sub compile_available_filter_values
	{
		my $self = shift;
		my $col = shift;
		
		my $class = $self->cdbi_class;
		my $dbh = $class->db_Main;
		
		# For use in the inner loop to make table monkiers unique
		my $monkier_sequence_num = 0;
		
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
			my $concat     = $link->get_stringify_sql;
			#die Dumper $concat if $col eq 'empid';
			#die Dumper $concat;
				
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
			my $monkier   = "";
			if($other_ref eq $self_ref)
			{
				# This is to handle subqueries that query the same table as the outer query.
				# For example, say we're trying to make a subquery for a column called 'parentid' that looks up the
				# name of the parent row in the same table - we've got to make the table monkiers unique for the query
				# to process correctly, since its the same table.
				$monkier   = $dbh->quote_identifier($link->table.(++$monkier_sequence_num));
				$other_ref = $monkier;
			}
				
			#push @columns, "DISTINCT (SELECT $concat FROM $other_db.$table $monkier WHERE $other_ref.$primary=$self_ref.$self_field AND $link_clause) AS ".$dbh->quote_identifier($col);
			$linked_table = "$other_db.$table $monkier";
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
