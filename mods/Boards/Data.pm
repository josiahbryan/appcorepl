use strict;

package Boards::DbSetup;
{
# 	our $DbPassword = AppCore::Common->read_file('mods/ThemePHC/pci_db_password.txt');
# 	{
# 		$DbPassword =~ s/[\r\n]//g;
# 	}
	
	our @DbConfig = (
	
# 		db		=> 'phc',
# 		db_host		=> 'database',
# 		db_user		=> 'root',
# 		db_pass		=> $Boards::DbSetup::DbPassword,
	);
	
	our @PriKeyAttrs = (
		'extra'	=> 'auto_increment',
		'type'	=> 'int(11)',
		'key'	=> 'PRI',
		readonly=> 1,
		auto	=> 1,
	);
	
	# Reference in class meta as:
	# @Boards::DbSetup::DbConfig
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			Boards::SpamLog
			Boards::Group
			Boards::Post::Tag
			Boards::Post::Tag::Pair
			Boards::Post::Like
			Boards::Post
			Boards::Board
			Boards::VideoProvider
			Boards::TextFilter
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
}

package Boards::SpamLog;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_SPAMLOG || 'boards_spamlog',
		
		schema	=> 
		[
			{ field => 'lineid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'userid',			type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'subroutine',		type => 'varchar(255)' },
			{ field	=> 'spam_method',		type => 'varchar(255)' },
			{ field	=> 'text',			type => 'text' },
			{ field => 'extra_info',		type => 'text'},
		],	
	});
}


package Boards::TextFilter;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_TEXTFILTERS || 'boards_textfilters',
		
		schema	=> 
		[
			{ field => 'filterid',		type	=> 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'name',		type	=> 'varchar(255)' },
			{ field	=> 'description',	type	=> 'varchar(255)' },
			{ field	=> 'controller',	type	=> 'varchar(255)' },
			{ field	=> 'is_enabled',	type	=> 'int(1)', null=>0, default => 1 },
		],	
	});
	
	sub register
	{
		my $filter_ref = undef;
		undef $@;
		eval
		{
			my $pkg = shift;
			$pkg = ref $pkg if ref $pkg;
			
			my $name = shift;
			my $diz = shift;
			
			my $self = $pkg->find_or_create({controller=>$pkg});
			
			$self->name($name) if $self->name ne $name;
			$self->description($diz) if $self->description ne $diz;
			$self->update if $self->is_changed;
			
			$filter_ref = $self;
			
		};
		warn $@ if $@;
		
		return $filter_ref;
	}
	
	sub filter_text
	{
		my $self = shift;
		my $textref = shift;
		
		# Dummy: Do nothing here.
		# Subclasses override filter_text() to do the fitlering 
		
		return 1;
	}
}

package Boards::VideoProvider;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_VIDEOPROVIDERS || 'boards_videoproviders',
		
		schema	=> 
		[
			{ field => 'providerid',	type	=> 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'name',		type	=> 'varchar(255)' },
			#{ field	=> 'description',	type	=> 'varchar(255)' },
			{ field	=> 'controller',	type	=> 'varchar(255)' },
			{ field	=> 'is_enabled',	type	=> 'int(1)', null=>0, default => 1 },
		],	
	});
	
	our %PackageConfig;
	sub config
	{
		my $self = shift;
		my $pkg = ref $self ? ref $self : $self;
		#use Data::Dumper;
		#print STDERR __PACKAGE__."::config(): '$pkg', all config: ".Dumper(\%PackageConfig);
		return $PackageConfig{$pkg}; 
	}
	
	sub register
	{
		my $filter_ref = undef;
		undef $@;
		eval
		{
			my $pkg = shift;
			$pkg = ref $pkg if ref $pkg;
			
			my $config = shift;
			
			my $self = $pkg->find_or_create({controller=>$pkg});
			
			$self->name($config->{name}) if $self->name ne $config->{name};
			#$self->description($diz) if $self->description ne $diz;
			$self->update if $self->is_changed;
			
			$PackageConfig{$pkg} = $config;
			
# 			use Data::Dumper;
# 			print STDERR __PACKAGE__."::register(): '$pkg' config: ".Dumper($config);
			
			$filter_ref = $self;
			
		};
		warn $@ if $@;
		
		return $filter_ref;
	}
	
	sub process_url
	{
		my $self = shift;
		my $url = shift;
		
		# Dummy: Do nothing here.
		# Subclasses override process_url() to do the processing 
		
		return $url;
	}
}

package Boards::Group;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_GROUP || 'board_groups',
		
		schema	=> 
		[
			{ field => 'groupid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'managerid',			type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'title',			type => 'text' },
			{ field	=> 'sort_key',			type => 'varchar(255)' },
			{ field => 'hidden',			type => 'int'},
		],	
	});
}

package Boards::Post::Tag;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_TAGS || 'board_post_tags',
		
		schema	=> 
		[
			{ field => 'tagid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'tag',			type => 'varchar(255)' },
			{ field => 'hidden',			type => 'int'},
			{ field => 'deleted',			type => 'int'},
		],	
		
		has_many	=> ['Boards::Post::Tag::Pair'],
	});
	
	sub get_tag { shift->by_field(tag=>shift) }
	sub posts 
	{
		my $self = shift;
		my @posts = Boards::Post::Tag::Pair->search(tagid => $self);
		return map { $_->postid } @posts;
	}
}

package Boards::Post::Tag::Pair;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_TAGPAIR || 'board_post_tag_pairs',
		
		class_title	=> 'Tag Pair List',
		class_noun	=> 'Tag Pair',
		
		schema	=> 
		[
			{ field => 'lineid',	type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'tagid',	type => 'int',	linked => 'Boards::Post::Tag' },
			{ field	=> 'postid',	type => 'int',	linked => 'Boards::Post' },
			
		],	
	});
	
	sub stringify_fmt { ('#tagid', ' - ','#postid') }
}

package Boards::Post::Like;
{
	use base 'AppCore::DBI';
	
	my $table = $AppCore::Config::BOARDS_DBTBL_POSTLIKES || 'board_post_likes';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $table,
		
		schema	=> 
		[
			{ field => 'lineid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'postid',			type => 'int', linked => 'Boards::Post',  default => 0 },
			{ field	=> 'userid',			type => 'int', linked => 'AppCore::User', default => 0 },
			{ field => 'name',			type => 'varchar(255)'},
			{ field => 'email',			type => 'varchar(255)'},
			{ field => 'photo',			type => 'varchar(255)'},
			{ field	=> 'timestamp',			type => 'timestamp' },
		],	
	});
	
	my $dbh = __PACKAGE__->db_Main;
	my $q_cmt_likes 	= $dbh->prepare('select count(lineid) as count from '.$table.' where postid=? and (userid!=? or userid is null or userid=0)');
	my $q_youlike_cmt 	= $dbh->prepare('select count(lineid) as count from '.$table.' where postid=? and userid=?');
	my $q_cmt_other_names	= $dbh->prepare('select distinct display from '.$table.' p,'.AppCore::User->table.' e where p.userid=e.userid and p.userid is not null and p.postid=? and p.userid!=? order by display');
	my $q_cmt_nonuser_names	= $dbh->prepare('select distinct name from '.$table.' p where p.postid=? and (p.userid!=? or p.userid is null) order by name');
	
	
	sub like_data_for_post
	{
		my $self = shift;
		my $postid = shift;
		my $ref = shift || {};
		my $user = AppCore::Common->context->user;
		my $userid = $user && $user->id ? $user->id : 0;
		
		$q_cmt_likes->execute($postid,$userid);
		$q_youlike_cmt->execute($postid,$userid) if $userid;
				
		$ref->{others_like} = $q_cmt_likes->fetchrow_hashref->{count};
		$ref->{you_like}    = $userid ? $q_youlike_cmt->fetchrow_hashref->{count} : 0;
		
		$q_cmt_other_names->execute($postid,$userid);
		$q_cmt_nonuser_names->execute($postid,$userid);
		
		my @list;
		push @list, $_->{display} while $_ = $q_cmt_other_names->fetchrow_hashref;
		push @list, $_->{name}    while $_ = $q_cmt_nonuser_names->fetchrow_hashref;
		
		# Make names unique (case insensitive)
		my %tmp = map { lc $_ => $_ } @list;
		@list = sort {$a cmp $b} grep { $_ ne '' } values %tmp;
		
		my $diff = $ref->{others_like} - scalar(@list);
		push @list, "$diff anonymous" if $diff > 0;
		if(@list >= 2)
		{
			my $last = pop @list;
			push @list, "and $last";
		}
		$ref->{others_like_names} = @list == 2 ? join(" ", @list) : join(", ",@list);
		$ref->{others_like_names_list} = join("\n", @list);
		
		#print STDERR "Post: $postid, Dump:".Dumper($ref);
		
		#print STDERR "like_data_for_post: post: $postid, userid: $userid, u: $ref->{you_like}, o:$ref->{others_like}, n:$ref->{others_like_names}\n";
		return $ref;
	}
};

package Boards::Post;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_POST || 'board_posts',
		
		schema	=> 
		[
			{ field => 'postid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'boardid',			type => 'int', linked => 'Boards::Board', default => 0 },
			{ field => 'poster_name',		type => 'varchar(255)'},
			{ field => 'poster_email',		type => 'varchar(255)'},
			{ field => 'poster_photo',		type => 'varchar(255)'},  # not used yet.......
			{ field	=> 'posted_by',			type => 'int',	linked => 'AppCore::User', default => 0 },
			#{ field => 'posted_at',			type => 'datetime' }, # not used for legacy reasons for now
			{ field	=> 'timestamp',			type => 'datetime' }, # leave as datetime for legacy reasons for now
			{ field	=> 'updated_time',		type => 'timestamp' },
			{ field	=> 'top_commentid',		type => 'int', linked => 'Boards::Post', default => 0 },
			{ field	=> 'parent_commentid',		type => 'int', linked => 'Boards::Post', default => 0 },
			{ field	=> 'last_commentid',		type => 'int', linked => 'Boards::Post', default => 0 },
			{ field => 'subject',			type => 'text'},
			{ field => 'text',			type => 'longtext'},
			{ field => 'extra_data',		type => 'longtext'},
			{ field => 'post_class',		type => 'varchar(255)' }, # An arbitrary classification, such as 'video', 'photo', 'link', 'text', or just empty... # TODO Should this be a Foreign Key ... e.g. classid?
			#{ field => 'attribute_data',		type => 'longtext'},  # Legacy name of extra_data
			{ field => 'folder_name',		type => 'varchar(255)' },
			#{ field => 'fake_folder_name',		type => 'varchar(255)' }, # Legacy name of folder_name
			{ field => 'deleted',			type => 'int', default => 0},
			{ field => 'num_views',			type => 'int', default => 0},
			{ field => 'num_replies',		type => 'int', default => 0},
			{ field => 'ticker_priority',		type => 'int', default => 0},
			{ field => 'ticker_class',		type => 'varchar(255)' },
			{ field => 'hidden',			type => 'int(1)', null => 0, default => 0 },
			#{ field => 'fb_post_id',		type => 'varchar(255)', default => '' },
			{ field => 'external_id',		type => 'varchar(255)', default => '' },
			{ field => 'external_source',		type => 'varchar(255)', default => '' },
			{ field => 'external_url',		type => 'varchar(255)', default => '' },
			
			
		],	
		
		has_many	=> ['Boards::Post::Tag::Pair', 'Boards::Post::Like'],
	});
	
	sub tags
	{
		my $self = shift;
		my @tags = Boards::Post::Tag::Pair->search(postid => $self);
		return map { $_->tagid } @tags;
	}
	
	sub get_tagged
	{
		my $class = shift;
		my $tag = shift;
		if( ! UNIVERSAL::isa($tag,'Boards::Post::Tag'))
		{
			$tag = Boards::Post::Tag->find_or_create(tag=>$tag);
		}
		my @tags = Boards::Post::Tag::Pair->search(tagid => $tag);
		return map { $_->postid } @tags;
	}
	
	sub add_tag
	{
		my $self = shift;
		my $tag = shift;
		
		if( ! UNIVERSAL::isa($tag,'Boards::Post::Tag'))
		{
			$tag = Boards::Post::Tag->find_or_create(tag=>$tag);
		}
		
		Boards::Post::Tag::Pair->find_or_create(tagid=>$tag,postid=>$self);
		
		return $tag;
	}
	
	sub remove_tag
	{
		my $self = shift;
		my $tag = shift;
		
		if( ! UNIVERSAL::isa($tag,'Boards::Post::Tag'))
		{
			$tag = Boards::Post::Tag->by_field(tag=>$tag);
			return undef if !$tag;
		}
		
		return Boards::Post::Tag::Pair->search(tagid=>$tag)->delete_all;
	}
	
	__PACKAGE__->add_trigger( after_update => sub
	{
		my $self = shift;
		
		Boards::Board->sync_counts();
		
	});
	
	__PACKAGE__->add_trigger( after_create => sub
	{
		my $self = shift;
		
		Boards::Board->sync_counts();
		
		if(!$self->boardid)
		{
			die "Wierd - $self doesnt have a boardid (".$self->boardid.")";
		}

		$self->boardid->last_commentid($self);
		$self->boardid->update();
		
		if($self->top_commentid && $self->top_commentid->id)
		{
			$self->top_commentid->num_replies($self->top_commentid->num_replies + 1);
			$self->top_commentid->last_commentid($self);
			$self->top_commentid->update;
		}
	});
	
	sub data#()
	{
		my $self = shift;
		my $dat  = $self->{_user_data_inst} || $self->{_data};
		if(!$dat)
		{
			return $self->{_data} = Boards::Post::GenericDataClass->_init($self);
		}
		return $dat;
	}
	
# Method: set_data($ref)
# If $ref is a hashref, it creates a new EAS::Workflow::Instance::GenericDataClass wrapper and sets that as the data class for this instance.
# If $ref is a reference (not a CODE or ARRAY), it checks to see if $ref can get,set,is_changed, and update - if true,
# it sets $ref as the object to be used as the data class.
	sub set_data#($ref)
	{
		my $self = shift;
		my $ref = shift;
		if(ref $ref eq 'HASH')
		{
			$self->{_data} = Boards::Post::GenericDataClass->new($self,$ref);
		}
		elsif(ref $ref && ref $ref !~ /(CODE|ARRAY)/)
		{
			foreach(qw/get set is_changed update/)
			{
				die "Cannot use ".ref($ref)." as a data class for Boards::Post: It does not implement $_()" if ! $ref->can($_);
			}
			
			$self->{_user_data_inst} = $ref;
		}
		else
		{
			die "Cannot use non-hash or non-object value as an argument to Boards::Post->set_data()";
		}
		
		return $ref;
	}
}


# Package: Boards::Post::GenericDataClass 
# Designed to emulate a very very simple version of Class::DBI's API.
# Provides get/set/is_changed/update. Not to be created directly, 
# rather you should retrieve an instance of this class through the
# Boards::Post::GenericDataClass->data() method.
# Note: You can use your own Class::DBI-compatible class as a data
# container to be returned by Boards::Post::GenericDataClass->data(). 
# Just call $post->set_data($my_class_instance).
# Copied from EAS::Workflow::Instance::GenericDataClass.
package Boards::Post::GenericDataClass;
{
	#use Storable qw/freeze thaw/;
	use JSON qw/to_json from_json/;
	use Data::Dumper;


# Method: _init($inst,$ref)
# Private, only to be initiated by the Post instance
	sub _init
	{
		my $class = shift;
		my $inst = shift;
		#print STDERR "Debug: init '".$inst->data_store."'\n";
		my $self = bless {data=>from_json($inst->extra_data ? $inst->extra_data  : '{}'),changed=>0,inst=>$inst}, $class;
		#print STDERR "Debug: ".Dumper($self->{data});
		return $self;
		
	}
	
	sub hash {shift->{data}}

# Method: get($k)
# Return the value for key $k
	sub get#($k)
	{
		my $self = shift;
		my $k = shift;
		return $self->{data}->{$k};
	}

# Method: set($k,$v)
# Set value for $k to $v
	sub set#($k,$v)
	{
		my $self = shift;#shift->{shift()} = shift;
		my ($k,$v) = @_;
		$self->{data}->{$k} = $v;
		$self->{changed} = 1;
		return $self->{$k};
	}

# Method: is_changed()
# Returns true if set() has been called
	sub is_changed{shift->{changed}}

# Method: update()
# Commits the changes to the workflow instance object
	sub update
	{
		my $self = shift;
		$self->{inst}->extra_data(to_json($self->{data}));
		#print STDERR "Debug: save '".$self->{inst}->data_store."'\n";
		return $self->{inst}->update;
	}
}

package Boards::Board;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::BOARDS_DBTBL_GROUP || 'boards',
		
		schema	=> 
		[
			{ field => 'boardid',			type => 'int', @Boards::DbSetup::PriKeyAttrs },
			{ field	=> 'managerid',			type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'groupid',			type => 'int',	linked => 'Boards::Group' },
			{ field	=> 'folder_name',		type => 'varchar(255)' },
			{ field => 'pageid',			type => 'int',	linked => 'Content::Page' },  # pageid replaces section_name because it gives us the proper URL thru which this board should be accessed
			{ field	=> 'section_name',		type => 'varchar(255)' }, ## TODO ?? Legacy ??
			{ field => 'forum_controller',		type => 'varchar(255)' }, # Still needed .. but should be in some 'advanced' part of the config UI
			{ field	=> 'title',			type => 'varchar(255)' },
			{ field	=> 'tagline',			type => 'varchar(255)' },
			{ field	=> 'description',		type => 'text' },
			{ field	=> 'lastupdated',		type => 'datetime' },
			{ field => 'num_views',			type => 'int'},
			{ field => 'num_replies',		type => 'int'},
			{ field => 'num_posts',			type => 'int'},
			{ field => 'num_reminders',		type => 'int'},
			{ field => 'auth_required',		type => 'int'},
			{ field => 'lastcomment',		type => 'datetime'},
			{ field	=> 'sort_key',			type => 'varchar(255)' },
			{ field	=> 'last_commentid',		type => 'int', linked => 'Boards::Post' },
			{ field => 'date_created',		type => 'datetime' },
			{ field => 'created_by',		type => 'int', linked => 'AppCore::User' },
			{ field => 'hidden',			type => 'int(1)', null => 0, default => 0 },
			{ field => 'enabled',			type => 'int(1)', null => 0, default => 1 },
			{ field => 'fb_sync_enabled',		type => 'int(1)', null => 0, default => 1 },
			{ field	=> 'fb_feed_id',		type => 'varchar(255)' },
			{ field	=> 'fb_access_token',		type => 'varchar(255)' },
			{ field	=> 'fb_feed_name',		type => 'varchar(255)' }, # only for display to the user - not "required" or really used
		],	
	});
	
	sub sync_counts
	{
		my $self = shift;
		#$self->db_Main->do(q{update boards b set num_replies = (select count(postid) from board_posts p where top_commentid !=0 and boardid = b.boardid and (select deleted from board_posts q where q.postid=p.top_commentid)=0)});
		#$self->db_Main->do(q{update boards b set num_posts   = (select count(postid) from board_posts p where top_commentid = 0 and boardid = b.boardid and deleted=0);});
	}
	
}

1;
