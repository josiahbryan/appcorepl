use strict;

package PHC::DbSetup;
{
	our $DbPassword = AppCore::Common->read_file('mods/ThemePHC/pci_db_password.txt');
	{
		$DbPassword =~ s/[\r\n]//g;
	}
	
	our @DbConfig = (
	
		db		=> 'phc',
		db_host		=> 'database',
		db_user		=> 'root',
		db_pass		=> $PHC::DbSetup::DbPassword,
	);
	
	# Reference in class meta as:
	# @PHC::DbSetup::DbConfig
}

package PHC::Blog;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'blogs',
		
		schema	=> 
		[
			{ field => 'blogid',			type => 'int', auto => 1},
			{ field	=> 'ownerid',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'folder_name',		type => 'varchar(255)' },
			{ field	=> 'title',			type => 'varchar(255)' },
			{ field	=> 'tagline',			type => 'varchar(255)' },
			{ field	=> 'description',		type => 'varchar(255)' },
			{ field	=> 'lastupdated',		type => 'datetime' },
			{ field => 'num_views',			type => 'int'},
			{ field => 'num_reminders',		type => 'int'},
			{ field => 'auth_required',		type => 'int'},
			{ field => 'lastcomment',		type => 'datetime'},
			{ field => 'enable_autosave',		type => 'int'},
		],	
	});
}

package PHC::Blog::Post;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'blog_posts',
		
		schema	=> 
		[
			{ field => 'postid',			type => 'int', auto => 1},
			{ field	=> 'boardid',			type => 'int',	linked => 'PHC::Board' },
			{ field	=> 'postdate',			type => 'datetime' },
			{ field => 'title',			type => 'varchar(255)'},
			{ field => 'content',			type => 'longtext'},
			{ field => 'num_views',			type => 'int'},
			{ field => 'draft_flag',		type => "enum('yes','no')"},
			{ field => 'draft_time',		type => 'datetime'},
		],	
	});
	
	__PACKAGE__->add_trigger(before_create	=> sub {
		my $post = shift;
		
		require 'ban_words_lib.pl';
		# Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
		my $clean = $post->text;
		$clean =~ s/<[^\>]*>//g; $clean = PHC::Web::Common->html2text($clean);
		$clean =~ s/[^\w]/ /g;
		$clean .= ' ';
		my ($weight,$matched) = PHC::BanWords::get_phrase_weight($clean);

		my $user = PHC::Web::Context->user;


		if($weight >= 5)
		{
			PHC::Chat->db_Main->do('insert into chat_rejected (posted_by,poster_name,message,value,list) values (?,?,?,?,?)',undef,
				$user,
				$user && $user->id ? $user->display : $post->poster_name,
				$post->text,
				$weight,
				join("\n ",@$matched)
			);

			print STDERR "===== BANNED ====\nPhrase: '".$post->text."'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n======
==========\n";
			die "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try
 again.\nYour original comment:\n".$post->text;
		}
		
		die Dumper $clean;
	
	});
	
		
}

package PHC::Blog::Comments;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'blog_comments',
		
		schema	=> 
		[
			{ field => 'commentid',			type => 'int', auto => 1},
			{ field	=> 'postid',			type => 'int',	linked => 'PHC::Blog::Post' },
			{ field => 'commentor',			type => 'varchar(255)'},
			{ field	=> 'timestamp',			type => 'timestamp' },
			{ field => 'subject',			type => 'varchar(255)'},
			{ field => 'email',			type => 'varchar(255)'},
			{ field => 'comment',			type => 'longtext'},
			{ field => 'parentcomment',		type => 'int'},
			{ field	=> 'commentor_userid',		type => 'int',	linked => 'PHC::User' },
		],	
	});
}


package PHC::WebBoard::Group;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'board_groups',
		
		schema	=> 
		[
			{ field => 'groupid',			type => 'int', auto => 1},
			{ field	=> 'managerid',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'title',			type => 'text' },
			{ field	=> 'sort_key',			type => 'varchar(255)' },
			{ field => 'hidden',			type => 'int'},
		],	
	});
}



package PHC::WebBoard::Post::Tag;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'board_post_tags',
		
		schema	=> 
		[
			{ field => 'tagid',			type => 'int', auto => 1},
			{ field	=> 'tag',			type => 'varchar(255)' },
			{ field => 'hidden',			type => 'int'},
			{ field => 'deleted',			type => 'int'},
		],	
		
		has_many	=> ['PHC::WebBoard::Post::Tag::Pair'],
	});
	
	sub get_tag { shift->by_field(tag=>shift) }
	sub posts 
	{
		my $self = shift;
		my @posts = PHC::WebBoard::Post::Tag::Pair->search(tagid => $self);
		return map { $_->postid } @posts;
	}
}

package PHC::WebBoard::Post::Tag::Pair;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'board_post_tag_pairs',
		
		class_title	=> 'Tag Pair List',
		class_noun	=> 'Tag Pair',
		
		schema	=> 
		[
			{ field => 'lineid',	type => 'int', auto => 1},
			{ field	=> 'tagid',	type => 'int',	linked => 'PHC::WebBoard::Post::Tag' },
			{ field	=> 'postid',	type => 'int',	linked => 'PHC::WebBoard::Post' },
			
		],	
	});
	
	sub stringify_fmt { ('#tagid', ' - ','#postid') }
}


package PHC::WebBoard::Post;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'board_posts',
		
		schema	=> 
		[
			{ field => 'postid',			type => 'int', auto => 1},
			{ field	=> 'boardid',			type => 'int', linked => 'PHC::WebBoard' },
			{ field => 'poster_name',		type => 'varchar(255)'},
			{ field => 'poster_email',		type => 'varchar(255)'},
			{ field	=> 'posted_by',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'timestamp',			type => 'timestamp' },
			{ field	=> 'top_commentid',		type => 'int', linked => 'PHC::WebBoard::Post' },
			{ field	=> 'parent_commentid',		type => 'int', linked => 'PHC::WebBoard::Post' },
			{ field	=> 'last_commentid',		type => 'int', linked => 'PHC::WebBoard::Post' },
			{ field => 'subject',			type => 'text'},
			{ field => 'text',			type => 'longtext'},
			{ field => 'attribute_data',			type => 'longtext'},
			{ field => 'fake_folder_name',		type => 'varchar(255)' },
			{ field => 'deleted',			type => 'int'},
			{ field => 'num_views',			type => 'int'},
			{ field => 'num_replies',		type => 'int'},
			{ field => 'ticker_priority',		type => 'int'},
			{ field => 'ticker_class',		type => 'varchar(255)' },
			
			
		],	
	});
	
	sub tags
	{
		my $self = shift;
		my @tags = PHC::WebBoard::Post::Tag::Pair->search(postid => $self);
		return map { $_->tagid } @tags;
	}
	
	sub get_tagged
	{
		my $class = shift;
		my $tag = shift;
		if( ! UNIVERSAL::isa($tag,'PHC::WebBoard::Post::Tag'))
		{
			$tag = PHC::WebBoard::Post::Tag->find_or_create(tag=>$tag);
		}
		my @tags = PHC::WebBoard::Post::Tag::Pair->search(tagid => $tag);
		return map { $_->postid } @tags;
	}
	
	sub add_tag
	{
		my $self = shift;
		my $tag = shift;
		
		if( ! UNIVERSAL::isa($tag,'PHC::WebBoard::Post::Tag'))
		{
			$tag = PHC::WebBoard::Post::Tag->find_or_create(tag=>$tag);
		}
		
		PHC::WebBoard::Post::Tag::Pair->find_or_create(tagid=>$tag,postid=>$self);
		
		return $tag;
	}
	
	sub remove_tag
	{
		my $self = shift;
		my $tag = shift;
		
		if( ! UNIVERSAL::isa($tag,'PHC::WebBoard::Post::Tag'))
		{
			$tag = PHC::WebBoard::Post::Tag->by_field(tag=>$tag);
			return undef if !$tag;
		}
		
		return PHC::WebBoard::Post::Tag::Pair->search(tagid=>$tag)->delete_all;
	}
	
	__PACKAGE__->add_trigger( after_update => sub
	{
		my $self = shift;
		
		PHC::WebBoard->sync_counts();
		
	});
	
	__PACKAGE__->add_trigger( after_create => sub
	{
		my $self = shift;
		
		PHC::WebBoard->sync_counts();
		
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
			return $self->{_data} = PHC::WebBoard::Post::GenericDataClass->_init($self);
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
			$self->{_data} = PHC::WebBoard::Post::GenericDataClass->new($self,$ref);
		}
		elsif(ref $ref && ref $ref !~ /(CODE|ARRAY)/)
		{
			foreach(qw/get set is_changed update/)
			{
				die "Cannot use ".ref($ref)." as a data class for PHC::WebBoard::Post: It does not implement $_()" if ! $ref->can($_);
			}
			
			$self->{_user_data_inst} = $ref;
		}
		else
		{
			die "Cannot use non-hash or non-object value as an argument to PHC::WebBoard::Post->set_data()";
		}
		
		return $ref;
	}
}


# Package: PHC::WebBoard::Post::GenericDataClass 
# Designed to emulate a very very simple version of Class::DBI's API.
# Provides get/set/is_changed/update. Not to be created directly, 
# rather you should retrieve an instance of this class through the
# PHC::WebBoard::Post::GenericDataClass->data() method.
# Note: You can use your own Class::DBI-compatible class as a data
# container to be returned by PHC::WebBoard::Post::GenericDataClass->data(). 
# Just call $post->set_data($my_class_instance).
# Copied from EAS::Workflow::Instance::GenericDataClass.
package PHC::WebBoard::Post::GenericDataClass;
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
		my $self = bless {data=>from_json($inst->attribute_data ? $inst->attribute_data  : '{}'),changed=>0,inst=>$inst}, $class;
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
		$self->{inst}->attribute_data(to_json($self->{data}));
		#print STDERR "Debug: save '".$self->{inst}->data_store."'\n";
		return $self->{inst}->update;
	}
}

package PHC::WebBoard;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'boards',
		
		schema	=> 
		[
			{ field => 'boardid',			type => 'int', auto => 1},
			{ field	=> 'managerid',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'groupid',			type => 'int',	linked => 'PHC::WebBoard::Group' },
			{ field	=> 'folder_name',		type => 'varchar(255)' },
			{ field	=> 'section_name',		type => 'varchar(255)' },
			{ field => 'forum_controller',		type => 'varchar(255)' },
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
			{ field	=> 'last_commentid',		type => 'int', linked => 'PHC::WebBoard::Post' },
		],	
	});
	
	sub sync_counts
	{
		my $self = shift;
		#$self->db_Main->do(q{update boards b set num_replies = (select count(postid) from board_posts p where top_commentid !=0 and boardid = b.boardid and (select deleted from board_posts q where q.postid=p.top_commentid)=0)});
		#$self->db_Main->do(q{update boards b set num_posts   = (select count(postid) from board_posts p where top_commentid = 0 and boardid = b.boardid and deleted=0);});
	}
	
}

package PHC::Event;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'events',
		
		schema	=> 
		[
			{ field => 'eventid',			type => 'int', auto => 1},
			{ field	=> 'contact_userid',		type => 'int',	linked => 'PHC::User' },
			{ field => 'contact_name',		type => 'varchar(255)' },
			{ field => 'contact_email',		type => 'varchar(255)' },
			{ field	=> 'event_text',		type => 'text' },
			{ field	=> 'page_details',		type => 'text' },
			{ field => 'is_weekly',			type => 'int(1)'},
			{ field	=> 'datetime',			type => 'datetime' },
			{ field => 'weekday',			type => 'int'},
			{ field => 'at_phc',			type => 'int(1)'},
			{ field => 'location',			type => 'text'},
			{ field => 'location_map_link',		type => 'text'},
			{ field	=> 'postid',			type => 'int',	linked => 'PHC::WebBoard::Post' },
			{ field => 'fake_folder_override',	type => 'int' },
			
		],	
	});
}

package PHC::News;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'news',
		
		schema	=> 
		[
			{ field => 'articleid',			type => 'int', auto => 1},
			{ field	=> 'posted_by',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'submited_by',		type => 'int',	linked => 'PHC::User' },
			{ field	=> 'contact_userid',		type => 'int',	linked => 'PHC::User' },
			{ field => 'contact_name',		type => 'varchar(255)' },
			{ field => 'contact_email',		type => 'varchar(255)' },
			{ field	=> 'title',			type => 'varchar(255)' },
			{ field	=> 'text',			type => 'text' },
			
			{ field	=> 'datetime',			type => 'datetime' },
			{ field	=> 'article_date',		type => 'datetime' },
			
			{ field	=> 'postid',			type => 'int',	linked => 'PHC::WebBoard::Post' },
		],	
	});
}

package PHC::Missions;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'missions',
		
		schema	=> 
		[
			{ field => 'missionid',			type => 'int', auto => 1},
			{ field	=> 'boardid',			type => 'int',	linked => 'PHC::WebBoard' },
			{ field	=> 'missionary_userid',		type => 'int',	linked => 'PHC::User' },
			{ field	=> 'description',		type => 'text' },
			{ field => 'city',			type => 'varchar(255)' },
			{ field	=> 'country',			type => 'varchar(255)' },
			{ field	=> 'mission_name',		type => 'varchar(255)' },
			{ field	=> 'family_name',		type => 'varchar(255)' },
			{ field	=> 'short_tagline',		type => 'varchar(255)' },
			{ field	=> 'location_title',		type => 'varchar(255)' },
			{ field => 'photo_url',			type => 'varchar(255)' },
			{ field	=> 'lat',			type => 'float' },
			{ field	=> 'lng',			type => 'float' },
			{ field => 'deleted',			type => 'int' },
		],	
	});
}

package PHC::VerseLookup;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'verse_ref_cache',
		
		schema	=> 
		[
			{ field => 'lineid',			type => 'int', auto => 1},
			{ field => 'verse_ref',			type => 'varchar(255)' },
			{ field => 'title',			type => 'text' },
			{ field => 'passage',			type => 'text' },
		]
	});
	
	
	my %passage_rejects = map {$_=>1} qw/version see almost on at/;
	
	my $sth_get = __PACKAGE__->db_Main->prepare('select title,passage from '.__PACKAGE__->table.' where verse_ref=?');
	
	my $VERSE_URL_BASE = 'http://www.biblegateway.com/passage/?version=31&search=';
	use Digest::MD5 qw( md5_hex );
	use HTML::Entities;

	sub get_verse_url
	{
		my $class = shift;
		my $ref = shift;
		
		my ($psg) = $ref =~ /(?:\d+\s*)?([A-Za-z]+)/;
		#print STDERR "$ref: $psg\n";
		
		return $ref if $passage_rejects{lc($psg)};
		
		return $ref if $ref =~ /([\.:]0\d|00$)/;
		
		$sth_get->execute($ref);
		if(my $data = $sth_get->fetchrow_hashref)
		{
			$data->{title} =~ s/\(New International Version\)/(NIV)/gi;
			my $raw = $data->{passage}.' - '.$data->{title};
			my $text = PHC::Web::Common->html2text($raw); $text =~ s/\n//g;
			$text =~ s/(^\s+|\s+$)//g;
			$text =~ s/\s{2,}/ /g;
			$text =~ s/ - BibleGateway.com navigation$/ - $ref/g;
			#$text =~ s/&quot;/\\&quot;/g;
			# onmouseover='Tip(\"".encode_entities($text)."\")' onmouseout=\"UnTip()\"
			return "<a href='${VERSE_URL_BASE}${ref}' title='".encode_entities($text)."'>$ref<\/a>";
			
		}
		else
		{
			my $md5 = md5_hex($ref);
			open(FILE,">/tmp/$md5.ref");
			print FILE $ref;
			close(FILE);
			#/var/www/phc/
			system("/var/www/phc/verse_lookup.pl /tmp/$md5.ref &");
			
			return "<a href='${VERSE_URL_BASE}${ref}' title='Lookup ".encode_entities($ref)." on BibleGateway.com...'>$ref<\/a>";
			
		}
	}
	
	sub tag_verses
	{
		my $class = shift;
		my $text = shift;
		
		my $ref = shift || $class;
		
		#$text =~ s/((?:\d\s)?(?:[A-Za-z]+) (?:[0-9]+)(?:[:\.](?:[0-9]*))?(?:\s*-\s*(?:[0-9]*))?)/$ref->get_verse_url($1)/segi;
		$text =~ s/\b((?:Genesis|Gen|Ge|Gn|Exodus|Exo|Ex|Exod|Leviticus|Lev|Le|Lv|Numbers|Num|Nu|Nm|Nb|Deuteronomy|Deut|Dt|Joshua|Josh|Jos|Jsh|Judges|Judg|Jdg|Jg|Jdgs|Ruth|Rth|Ru|1 Samuel|1 Sam|1 Sa|1Samuel|1S|I Sa|1 Sm|1Sa|I Sam|1Sam|I Samuel|1st Samuel|First Samuel|2 Samuel|2 Sam|2 Sa|2S|II Sa|2 Sm|2Sa|II Sam|2Sam|II Samuel|2Samuel|2nd Samuel|Second Samuel|1 Kings|1 Kgs|1 Ki|1K|I Kgs|1Kgs|I Ki|1Ki|I Kings|1Kings|1st Kgs|1st Kings|First Kings|First Kgs|1Kin|2 Kings|2 Kgs|2 Ki|2K|II Kgs|2Kgs|II Ki|2Ki|II Kings|2Kings|2nd Kgs|2nd Kings|Second Kings|Second Kgs|2Kin|1 Chronicles|1 Chron|1 Ch|I Ch|1Ch|1 Chr|I Chr|1Chr|I Chron|1Chron|I Chronicles|1Chronicles|1st Chronicles|First Chronicles|2 Chronicles|2 Chron|2 Ch|II Ch|2Ch|II Chr|2Chr|II Chron|2Chron|II Chronicles|2Chronicles|2nd Chronicles|Second Chronicles|Ezra|Ezr|Nehemiah|Neh|Ne|Esther|Esth|Es|Job|Job|Jb|Psalm|Pslm|Ps|Psalms|Psa|Psm|Pss|Proverbs|Prov|Pr|Prv|Ecclesiastes|Eccles|Ec|Qoh|Qoheleth|Song of Solomon|Song|So|Canticle of Canticles|Canticles|Song of Songs|SOS|Isaiah|Isa|Is|Jeremiah|Jer|Je|Jr|Lamentations|Lam|La|Ezekiel|Ezek|Eze|Ezk|Daniel|Dan|Da|Dn|Hosea|Hos|Ho|Joel|Joe|Jl|Amos|Am|Obadiah|Obad|Ob|Jonah|Jnh|Jon|Micah|Mic|Nahum|Nah|Na|Habakkuk|Hab|Hab|Zephaniah|Zeph|Zep|Zp|Haggai|Hag|Hg|Zechariah|Zech|Zec|Zc|Malachi|Mal|Mal|Ml|Matthew|Matt|Mt|Mark|Mrk|Mk|Mr|Luke|Luk|Lk|John|Jn|Jhn|Acts|Ac|Romans|Rom|Ro|Rm|1 Corinthians|1 Cor|1 Co|I Co|1Co|I Cor|1Cor|I Corinthians|1Corinthians|1st Corinthians|First Corinthians|2 Corinthians|2 Cor|2 Co|II Co|2Co|II Cor|2Cor|II Corinthians|2Corinthians|2nd Corinthians|Second Corinthians|Galatians|Gal|Ga|Ephesians|Ephes|Eph|Philippians|Phil|Php|Colossians|Col|Col|1 Thessalonians|1 Thess|1 Th|I Th|1Th|I Thes|1Thes|I Thess|1Thess|I Thessalonians|1Thessalonians|1st Thessalonians|First Thessalonians|2 Thessalonians|2 Thess|2 Th|II Th|2Th|II Thes|2Thes|II Thess|2Thess|II Thessalonians|2Thessalonians|2nd Thessalonians|Second Thessalonians|1 Timothy|1 Tim|1 Ti|I Ti|1Ti|I Tim|1Tim|I Timothy|1Timothy|1st Timothy|First Timothy|2 Timothy|2 Tim|2 Ti|II Ti|2Ti|II Tim|2Tim|II Timothy|2Timothy|2nd Timothy|Second Timothy|Titus|Tit|Philemon|Philem|Phm|Hebrews|Heb|James|Jas|Jm|1 Peter|1 Pet|1 Pe|I Pe|1Pe|I Pet|1Pet|I Pt|1 Pt|1Pt|I Peter|1Peter|1st Peter|First Peter|2 Peter|2 Pet|2 Pe|II Pe|2Pe|II Pet|2Pet|II Pt|2 Pt|2Pt|II Peter|2Peter|2nd Peter|Second Peter|1 John|1 Jn|I Jn|1Jn|I Jo|1Jo|I Joh|1Joh|I Jhn|1 Jhn|1Jhn|I John|1John|1st John|First John|2 John|2 Jn|II Jn|2Jn|II Jo|2Jo|II Joh|2Joh|II Jhn|2 Jhn|2Jhn|II John|2John|2nd John|Second John|3 John|3 Jn|III Jn|3Jn|III Jo|3Jo|III Joh|3Joh|III Jhn|3 Jhn|3Jhn|III John|3John|3rd John|Third John|Jude|Jud|Revelation|Rev|Re|The Revelation) (?:[0-9]+)(?:[:\.](?:[0-9]*))?(?:\s*-\s*(?:[0-9]*))?)/$ref->get_verse_url($1)/segi;
		
		return $text;
	}
	
	
	#
	
	sub get_verse
	{
		my $class = shift;
		my $ref = shift;
		
		#my $cache = PHC::VerseLookup->by_field(verse_ref=>$ref);
		#return $cache if $cache;
		
		my $url = $VERSE_URL_BASE . $ref;
		
		print STDERR "Downloading $url\n";
		my $data = LWP::Simple::get($url);
		
		#print STDERR "Data: [$data]\n";
		
		my ($passage_title) = $data =~ /<h3>([^\<]+)<\/h3>/;
		my ($passage_text) = $data =~ /<div class="result-text-style-normal">((?:.|\n)+)<\/div>/;
		
		my $idx = index(lc $passage_text,'</div>');
		$passage_text = substr($passage_text,0,$idx);
		
		print STDERR "Got Title: $passage_title\n";
		
		my $cache = $class->create({verse_ref=>$ref,title=>$passage_title,passage=>$passage_text});
		return $cache;
	}
	
	
};

package PHC::Family;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'families',
		
		schema	=> 
		[
			{ field => 'familyid',			type => 'int', auto => 1},
			{ field	=> 'father_userid',		type => 'int',	linked => 'PHC::User' },
			{ field	=> 'mother_userid',		type => 'int',	linked => 'PHC::User' },
			{ field	=> 'surname',			type => 'varchar(255)' },
			{ field	=> 'father',			type => 'varchar(255)' },
			{ field	=> 'mother',			type => 'varchar(255)' },
			{ field	=> 'display',			type => 'varchar(255)' },
			
			{ field	=> 'father_birthday',		type => 'date' },
			{ field	=> 'mother_birthday',		type => 'date' },
			{ field	=> 'anniversary',		type => 'date' },
			{ field	=> 'photo_file',		type => 'varchar(255)' },
			{ field	=> 'office_notes',		type => 'longtext' },
			{ field	=> 'public_bio',		type => 'longtext' },
			
		],	
	});
}


package PHC::Recording;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'recordings',
		
		schema	=> 
		[
			{ field => 'recordingid',		type => 'int', auto => 1},
			{ field	=> 'uploaded_by',		type => 'int',	linked => 'PHC::User' },
			{ field	=> 'upload_timestamp',		type => 'timestamp' },
			{ field	=> 'title',			type => 'varchar(255)' },
			{ field	=> 'file_path',			type => 'text' },
			{ field	=> 'web_path',			type => 'text' },
			{ field	=> 'datetime',			type => 'datetime' },
			{ field	=> 'duration',			type => 'float' },
			{ field	=> 'published',			type => 'int(1)' },
			{ field => 'sermon_track_num',		type => 'int' },
		],	
	});
}


package PHC::Recording::Track;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'recording_tracks',
		
		schema	=> 
		[
			{ field => 'trackid',			type => 'int', auto => 1},
			{ field	=> 'recordingid',		type => 'int',	linked => 'PHC::Recording' },
			{ field	=> 'tracknum',			type => 'integer' },
			{ field	=> 'file_path',			type => 'text' },
			{ field	=> 'web_path',			type => 'text' },
			{ field	=> 'duration',			type => 'float' },
		],	
	});
}

package PHC::Chat;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		@PHC::DbSetup::DbConfig,
		table	=> 'chat',
		
		schema	=> 
		[
			{ field => 'lineid',			type => 'int', auto => 1},
			{ field => 'poster_name',		type => 'varchar(255)'},
			{ field => 'poster_email',		type => 'varchar(255)'},
			{ field => 'url',		type => 'varchar(255)'},
			{ field	=> 'posted_by',			type => 'int',	linked => 'PHC::User' },
			{ field	=> 'timestamp',			type => 'timestamp' },
			{ field => 'text',			type => 'longtext'},
			{ field => 'attribute_data',			type => 'longtext'},
			{ field => 'deleted',			type => 'int'},
			{ field => 'hidden',			type => 'int'},
			{ field => 'private',			type => 'int'},
			{ field => 'private_to',			type => 'int', linked => 'PHC::User'},
		]
	});
}


1;
