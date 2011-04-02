# Package: AppCore::Auth
# Namespace for Authentication and user classes

# Class: AppCore::User
# Implentation of a 'person' or Entity in EAS terminology. Often used for User objects, should be what is returned by AppCore::Common->context->user.
package AppCore::User;
{
	
	use strict;
	
	use base 'AppCore::DBI';
	
	our $default_acl = ['EVERYONE'];
	
	__PACKAGE__->meta({
		class_noun	=> 'Users',
		class_title	=> 'Users Database',
		
		db		=> $AppCore::Config::USERS_DBNAME,
		table		=> $AppCore::Config::USERS_DBTABLE,
		
		schema	=>
		[
			{
				'field'	=> 'userid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'user',		type	=> 'varchar(255)' },
			{	field	=> 'pass',		type	=> 'varchar(255)' },
			{	field	=> 'email',		type	=> 'varchar(255)' },
			{	field	=> 'first',		type	=> 'varchar(255)' },
			{	field	=> 'last',		type	=> 'varchar(255)' },
			{	field	=> 'display',		type	=> 'varchar(255)' },
			# Path relative to $AppCore::Config::WWW_DOC_ROOT for the users image
			# However, I recommend using the 'get_photo' method to get an appropriate-sized photo (get_photo handles resizing and caching as necessary)
			{	field	=> 'photo',		type	=> 'varchar(255)' },
			{	field	=> 'notes',		type	=> 'text'	  },
			{	field	=> 'is_fbuser',		type	=> 'int(1)'	  },
			{	field	=> 'fb_token',		type	=> 'varchar(255)' },
			{	field	=> 'fb_token_expires',	type	=> 'datetime'     },
		]		
	
	});
	
		
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update('AppCore::User');	
		$self->mysql_schema_update('AppCore::User::Group');
		$self->mysql_schema_update('AppCore::User::GroupList');
 	}
	
	sub stringify_fmt { qw/#userid/ }

	
	use AppCore::AuthUtil;
	sub authenticate { AppCore::AuthUtil->authenticate(@_) }
	
	# 
	# our $ALT_STRINGS = 0;
	# # Group: CDBI-Specific
	# sub stringify_self { $ALT_STRINGS ? shift->display : shift->userid } 
	
	# # Group: BlueDB-Specific
	# #sub stringify { return shift->display }
	# sub stringify_fmt { qw/#display/ }
	
	# __PACKAGE__->meta({
	# 	class_noun	=> 'Person/Entity',
	# 	class_title	=> 'People',
	# 	sort		=>qw/display/, 
	# 	edit_acl	=>['!ADMIN'],
	# 	create_acl	=>['!ADMIN'],
	# 	read_acl	=>['!ADMIN','!timeclock-admin']
	# });
		
	# sub compose_where_clause
	# {
	# 	my $class = shift;
	# 	my %inq = %{shift()||{}};
	# 	my %types = %{shift()||{}};
	# 	my $gentab = shift;
	# 	
	# 	my $limit = shift;
	# 	$limit = -1 if !defined $limit;
	# 
	# 	my @clause;
	# 	my @args;
	# 	#my @tables = ($class->table);
	# 	
	# 	foreach my $dbcol (keys %types)
	# 	{
	# 		my $type = $types{$dbcol};
	# 		
	# 		if(!defined $inq{$dbcol} || $inq{$dbcol} eq '' || $inq{$dbcol} eq '*' || !$inq{$dbcol})
	# 		{
	# 			delete $inq{$dbcol};
	# 		}
	# 		else
	# 		{
	# 			if(lc $dbcol eq 'last' || lc $dbcol eq 'display')
	# 			{
	# 				my $validated_initials = 0;
	# 				if(length $inq{$dbcol} == 2)
	# 				{
	# 					my $sth = AppCore::DBI->dbh->prepare_cached('select userid from pci.employees where substr(first,1,1) = ? and substr(last,1,1)=? and deleted!="y" and category="Employee"',undef,1);
	# 					
	# 					$sth->execute(substr($inq{$dbcol},0,1),substr($inq{$dbcol},1,1));
	# 					my $userid = $sth->rows ? $sth->fetchrow_hashref->{userid} : undef;
	# 					if($userid)
	# 					{
	# 						push @clause, ' pci.employees.userid = ? ';
	# 						push @args, $userid;
	# 						$validated_initials = 1;
	# 					}
	# 				}
	# 				
	# 				if(!$validated_initials)
	# 				{
	# 				
	# 					my ($first,$last) = split/\s+/,$inq{$dbcol};
	# 					$first=~s/\.//g;
	# 					my $name = '%'.$first.'%'.$last.'%';
	# 					
	# 					$inq{$dbcol} =~ s/\*/\%/g;
	# 					
	# 					my $string = ($types{$dbcol}||'') eq 'String';
	# 					$inq{$dbcol} = $string ? "\%$inq{$dbcol}\%" :  $inq{$dbcol};
	# 					
	# 					
	# 					
	# 					my %tables = ('pci.timeclock_users'=>'clocknum','pci.computer_users'=>'user','pci.phone_users'=>'ext');
	# 					my @pids;
	# 					#print STDERR Dumper \%tables;
	# 					foreach my $table (keys %tables)
	# 					{
	# 						my $sth = AppCore::DBI->dbh->prepare_cached('select userid from '.$table.' where `'.$tables{$table}.'` like ?',undef,1);
	# 						$sth->execute($inq{$dbcol});
	# 						next if $limit>0 && $sth->rows>$limit;
	# 						#print STDERR "\$limit=$limit, \$sth->rows=".$sth->rows."\n";
	# 						push @pids, $_->{userid} while $_ = $sth->fetchrow_hashref;
	# 					}
	# 					
	# 					push @clause, @pids ? " (pci.employees.`display` like ? or pci.employees.`last` like ? or pci.employees.`display` like ? or pci.employees.`userid` in (".join(',',@pids)."))" : " (pci.employees.`display` like ? or pci.employees.`last` like ? or pci.employees.`display` like ?)";
	# 					
	# 					#print STDERR "\$name=$name\n";
	# 					push @args, $name;
	# 					push @args, $inq{$dbcol};
	# 					push @args, $inq{$dbcol};
	# 				}
	# 			}
	# 			else
	# 			{
	# 				$inq{$dbcol} =~ s/\*/\%/g;
	# 				
	# 				my $string = ($types{$dbcol}||'') eq 'String';
	# 				$inq{$dbcol} = $string ? "\%$inq{$dbcol}\%" :  $inq{$dbcol};
	# 				
	# 				push @clause, "`$dbcol` ". ($string?' like ' : '=').' ? ';
	# 				push @args, $inq{$dbcol};
	# 			}
	# 		}
	# 		
	# 		
	# 	}
	# 	
	# 	#push @args, $inq{$_} foreach @key_list;
	# 	
	# 	
	# 	my $cl = join ' and ',@clause;
	# 	
	# 	#die Dumper \%inq, \@clause, \@args, \@key_list, $cl;
	# 	#print 
	# 	
	# 	
	# 	$cl = '1' if !$cl || $cl eq '';
	# 	#my $col0 = $columns[0]->dbcolumn;
	# 	
	# 	#print STDERR Dumper ''.$class,\%inq,\%types,"cl=",$cl,\@args;
	# 	#print STDERR __PACKAGE__.": compose_where_clause: \$cl=[$cl], args=[".join('|',@args)."]\n";
	# 	
	# 		
	# 	#my ($tables,$cl2,@args2) = AppCore::DBI->apply_user_filters($gentab);
	# 	#$cl .= " and $cl2";
	# 	#push @args, @args2;
	# 	
	# 	return (undef,$cl,@args); #('`'.join('`,`',@tables).'`',$cl,@args);
	# 
	# }
	
	
	
	# Group: ACL Utilities
	sub member_of
	{
		my $self = shift;
		my $name = shift;
		#die $name;
		
		return $name if $self->user eq $name;
		
		my $gid = group_id($name);
		return 0 if !$gid;
		
		my $user_groups = $self->user_acls;
		return 0 if !$user_groups;
		
		my %map = map {$_=>1} @$user_groups;
		return 1 if exists $map{$gid};
		
		return 0;
	}
	
	# Package function, not a method
	my %group_name_cache;
	sub group_id
	{
		my $name = shift;
		return $group_name_cache{$name} if exists $group_name_cache{$name};
		
		my $q_name = AppCore::DBI->dbh($AppCore::Config::USERS_DBNAME)->prepare('select `groupid` from `user_groups` where `name`=?');
		my $res = $q_name->execute($name);
		
		if($res)
		{
		
			my $id = $q_name->rows ? $q_name->fetchrow_hashref->{groupid} : undef;
			$group_name_cache{$name} = $id;
			
		#	die Dumper $name,$id,$q_name->rows;
			#print STDERR "group_id($name)=$id\n";
			return $id;
		}
		else
		{
			die "group_id($name): Error in preparing SQL statement";
		}
	
	}
	
	my %user_acl_cache;
	sub user_acls
	{
		my $self = shift;
		my $userid = $self->userid;
		
		return $user_acl_cache{$userid} if exists $user_acl_cache{$userid};
	
		my $q_acls = AppCore::DBI->dbh($AppCore::Config::USERS_DBNAME)->prepare('select groupid from `user_group_list` where userid=?');
		$q_acls->execute($userid);
		
		#die Dumper $sid;
		
		my @list;
		while(my $ref = $q_acls->fetchrow_hashref)
		{
			push @list, $ref->{groupid};
		}
		
		$user_acl_cache{$userid} = \@list;
	
		#die Dumper \@list;	
		return \@list;
	}
	
	sub check_acl
	{
		my $self = shift;
		
		if(!ref $self)
		{
			warn "Warning: Cannot call check_acl() as a class function, you must call it as a method of a valid AppCore::User object, e.g. \$ref->check_acl() not EAS::User->check_acl";
			eval
			{
				if($self->SUPER::can('check_acl'))
				{
					return $self->SUPER::check_acl(@_);
				}
				else
				{
					return undef;
				}	
			};
			if($@)
			{
				warn "Warning: While trying to call \$self->SUPER::check_acl(), an error was thrown: $@";
				return 0;
			}
		}
		
		my $acl = shift || $default_acl;
		
		
		if(ref $acl && $acl->[0] eq 'ADMIN' && $self->userid == 1)
		{
			return 1;
		}
		
		#print header;
		
		my $ok_flag = 0;
		
		#return $acl eq undef if $data eq undef;		# Not logged in
		
		# Apply default ACL list if none specified by the app
		my $ALL = group_id('EVERYONE');
		$acl = [$ALL] if !defined $acl;
		
		
		#print "mark: acl:$app->{acl},keys:".join('|',@{$app->{acl}})."\n";
		
		#foreach(keys %{$data})
		#{
		#	print "user key $_ = $data->{$_}\n";
		#}
		#print Dumper($data),print_stack_trace();
		
		my %hash;
		my %not_hash;
		my $not_has_rx = 0;
		foreach( @$acl )
		{
			my $tmp = group_id($_);
			my $key = (!defined $tmp)?$_:$tmp;
			#print "map: $key => 1\n";
			if ($key=~/^\!/)
			{
				$key=~s/^\!//g;
				$not_hash{$key} = $_;
				$not_has_rx = 1 if $key=~/^#/;
			}
			else
			{
				$hash{$key} = $_;
			}
		}
		
		#dumper $not_has_rx if $app->{app_id} eq 'dial';
		
		#print "mark: hash keys:".join('|',keys %hash)."\n";
		
		
		#print STDERR "Debug clasdata: \$self='$self', ref='".ref($self)."'\n";
		# Add support for exclusion '!#ext-', eg exclusion hashes and regex matching on hashes
		my $denied = 0;
		return $denied if exists $not_hash{$self->user};
		if($not_has_rx)
		{
			foreach my $k (keys %not_hash)
			{
				my $dup = $k;
				return $denied if ($dup=~s/^#\w//g) && ($self->user =~ /$dup/);
			}
		}
		
		my $qn = (keys %not_hash)?AppCore::DBI->dbh($AappCore::Config::USERS_DBNAME)->prepare('select name from user_groups where groupid=? limit 1'):undef;
			
		# Try to match groups the user is in with groups in the app's ACL list
		my $user_groups = $self->user_acls;
		foreach(@$user_groups)
		{
			# Check DENY stuff
			if(keys %not_hash)
			{
				$qn->execute($_);
				my $key = ($qn->rows)?$qn->fetchrow_hashref()->{name}:$_;
				
				return $denied if exists $not_hash{$key};
				if($not_has_rx)
				{
					foreach my $k (keys %not_hash)
					{
						my $dup = $k;
						return 0 if ($dup=~s/^#(\w)/$1/g) && ($key=~/$dup/);
						#dumper $k,$key if $self->{current_user}->{userid} eq '157'; #$app->{app_id} eq 'dial' && $self->{q}->param('s') eq 'sp';
					}
				}
			}
			
			
			# Now check allow
			return $hash{$_} if exists $hash{$_}; # return group name that was matched
		}
		
		return $self->user if exists $hash{$self->user}; # If ACL lists username explicitly, return valid flag 
			# return username that was matched
		
		# Now for the defaults
		return 'EVERYONE' if exists $hash{$ALL}; 
		
		# Final cach-all: Admin access
		my $ADMIN = group_id('ADMIN');
		foreach(@$user_groups)
		{
			return 'ADMIN' if $_ eq $ADMIN;
		}
		
		return 0;
	}
};	


package AppCore::User::Group;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Groups',
		class_title	=> 'Group Database',
		
		db		=> $AppCore::Config::USERS_DBNAME,
		table		=> 'user_groups',
		
		schema	=>
		[
			{
				'field'	=> 'groupid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'name',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'notes',		type	=> 'text'	},
		]		
	
	});
	
	sub by_name
	{
		my $g = shift;
		my $name = shift;
		my @list = $g->search(name=>$name);
		return @list ? shift @list : @list;
	}
	
	sub email_list
	{
		my $self = shift;
		my @lines = AppCore::User::GroupList->search(groupid=>$self);
		my @list;
		foreach my $line (@lines)
		{
			my $e = $line->userid;
			if($e->compref)
			{
				push @list, $e->email;
			}
		}
		return @list;	
	}
	
	sub users
	{
		my $self = shift;
		my @lines = AppCore::User::GroupList->search(groupid=>$self);
		my @list;
		foreach my $line (@lines)
		{
			push @list, $line->userid;
		}
		return @list;	
	}
};

package AppCore::User::GroupList;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'User/Group Connection',
		class_title	=> 'User/Group Connection Database',
		
		db		=> $AppCore::Config::USERS_DBNAME,
		table		=> 'user_group_list',
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'userid',	type	=> 'int(11)',	linked => 'AppCore::User'  },
			{	field	=> 'groupid',	type	=> 'int(11)',	linked => 'AppCore::Group' },
			
		]
	});
	
};	


1;
