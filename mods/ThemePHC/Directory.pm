use strict;

package PHC::Directory::Family;
{
	use base 'AppCore::DBI';
	
	our @PriKeyAttrs = (
		'extra'	=> 'auto_increment',
		'type'	=> 'int(11)',
		'key'	=> 'PRI',
		readonly=> 1,
		auto	=> 1,
	);
	
	__PACKAGE__->meta(
	{
		# Cheating a bit...
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::PHC_DIRECTORY_DBTBL || 'directory',
		
		schema	=> 
		[
			{ field => 'familyid',			type => 'int', @PriKeyAttrs },
			{ field	=> 'userid',			type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'spouse_userid',		type => 'int',	linked => 'AppCore::User' },
			{ field => 'first',			type => 'varchar(255)' },
			{ field	=> 'last',			type => 'varchar(255)' },
			{ field	=> 'photo_num',			type => 'varchar(255)' },
			{ field	=> 'incomplete_flag',		type => 'int(1)', null =>0, default =>0 },
			{ field	=> 'birthday',			type => 'varchar(255)' },
			{ field	=> 'cell',			type => 'varchar(255)' },
			{ field => 'email',			type => 'varchar(255)' },
			{ field => 'home',			type => 'varchar(255)' },
			{ field	=> 'address',			type => 'varchar(255)' },
			{ field	=> 'p_cell_dir',		type => 'int(1)', null =>0, default =>1 },
			{ field	=> 'p_cell_onecall',		type => 'int(1)', null =>0, default =>1 },
			{ field	=> 'p_email_dir',		type => 'int(1)', null =>0, default =>1 },
			{ field => 'spouse',			type => 'varchar(255)' },
			{ field => 'spouse_birthday',		type => 'varchar(255)' },
			{ field => 'spouse_cell',		type => 'varchar(255)' },
			{ field => 'spouse_email',		type => 'varchar(255)' },
			{ field	=> 'p_spouse_cell_dir',		type => 'int(1)', null =>0, default =>1 },
			{ field	=> 'p_spouse_cell_onecall',	type => 'int(1)', null =>0, default =>1 },
			{ field	=> 'p_spouse_email_dir',	type => 'int(1)', null =>0, default =>1 },
			{ field => 'anniversary',		type => 'varchar(255)' },
			{ field => 'comments',			type => 'text' },
			{ field	=> 'display',			type => 'varchar(255)' },
			
			{ field => 'timestamp',			type => 'timestamp' },
			
			{ field	=> 'lat',			type => 'float' },
			{ field	=> 'lng',			type => 'float' },
			{ field => 'deleted',			type => 'int' },
		],	
	});
};

package PHC::Directory::Child;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		# Cheating a bit...
		@Boards::DbSetup::DbConfig,
		table	=> $AppCore::Config::PHC_DIRECTORY_DBTBL || 'directory_kids',
		
		schema	=> 
		[
			{ field => 'childid',			type => 'int', @PHC::Directory::Family::PriKeyAttrs },
			{ field	=> 'familyid',			type => 'int',	linked => 'PHC::Directory::Family' },
			{ field	=> 'child_familyid',		type => 'int',	linked => 'PHC::Directory::Family' },
			{ field	=> 'child_userid',		type => 'int',	linked => 'AppCore::User' },
			{ field => 'first',			type => 'varchar(255)' },
			{ field	=> 'last',			type => 'varchar(255)' },
			{ field	=> 'display',			type => 'varchar(255)' },
			{ field	=> 'cell',			type => 'varchar(255)' },
			{ field => 'email',			type => 'varchar(255)' },
			{ field	=> 'birthday',			type => 'varchar(255)' },
			{ field => 'comments',			type => 'text' },
			
			{ field => 'timestamp',			type => 'timestamp' },
			
			{ field => 'deleted',			type => 'int' },
		],	
	});
};

package PHC::Directory;
{
	# To cache the data in the spreadsheet so we dont have to parse it every reqyest
	use Storable qw/store retrieve/;
	
	sub read_legacy_xls
	{
		my $class = shift;
		my $data_file = shift || 'LegacyData.xls';
		# To read the data spreadsheet
		use Spreadsheet::ParseExcel;
	
		die "File '$data_file' doesn't exist!\n" if !-f $data_file;
		
		my $parser   = Spreadsheet::ParseExcel->new();
		my $workbook = $parser->parse($data_file);
		
		if ( !defined $workbook ) {
			die $parser->error(), ".\n";
		}
		
		my @worksheets = $workbook->worksheets();
		my $worksheet = shift @worksheets;
		
		my ( $row_min, $row_max ) = $worksheet->row_range();
		my ( $col_min, $col_max ) = $worksheet->col_range();
		
		# skip headers
		$row_min ++;
		
		sub xls_value($)
		{
			my $cell = shift;
			if($cell)
			{
				return  $cell->value();
			}
			else
			{
				return undef;
			}
		}
		
		my @entries;
		
		for my $row ( $row_min .. $row_max ) 
		{
			my $col_idx = 0;
			
			my %entry;
			
			$entry{first}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{last} 			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{photo_num}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{incomplete_flag}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{birthday}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{cell}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{email}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{home}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{adress}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_cell_dir}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_cell_onecall}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_email_dir}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{spouse}			= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{spouse_birthday}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{spouse_cell}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{spouse_email}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_spouse_cell_dir}	= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_spouse_cell_onecall} 	= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{p_spouse_email}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{anniversary}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			$entry{comments}		= xls_value $worksheet->get_cell( $row, $col_idx++ );
			
			my @kids;
			for(1..8)
			{
				my $name	= xls_value $worksheet->get_cell( $row, $col_idx++ );
				my $bday	= xls_value $worksheet->get_cell( $row, $col_idx++ );
				
				$name =~ s/(^\s+|\s+$)//g;
				push @kids, { name=>$name, bday=>$bday } if $name;
			}
			
			$entry{kids} = \@kids;
			
			if($entry{last})
			{
				#print "$last	/	$entry{first}\n";
				my $name = $entry{first};
				$name .= ' & '.$entry{spouse} if $entry{spouse};
				$name .= ' '.$entry{last};
				
				$entry{display} = $name;
		
				push @entries, \%entry;
				
				if($entry{incomplete_flag})
				{
					#print "Info Sheet: $name\n";
				}
			}
			
		}
		
		@entries = sort { lc $a->{last} cmp lc $b->{last} || lc $a->{first} cmp lc $b->{first} } @entries;
			

		return \@entries;
	}
	
	sub load_directory
	{
		my $www_path = $AppCore::Config::WWW_DOC_ROOT;
# 		my $www_path = '/var/www/phc';
# 		my $data_file = $www_path.'/Data.xls';
# 		my $cache_file = '/tmp/phc-directory.storable';
# 		if(-f $cache_file)
# 		{
# 			my $cache_mtime = (stat($cache_file))[9];
# 			my $data_mtime = (stat($data_file))[9];
# 			if($data_mtime <= $cache_mtime)
# 			{
# 				return retrieve($cache_file);
# 			}
# 		}
# 		

		my @fams = PHC::Directory::Family->retrieve_from_sql('1 order by last, first');
		foreach my $fam (@fams)
		{
			$fam->{$_} = $fam->get($_) foreach $fam->columns;
			
			my @kids = PHC::Directory::Child->retrieve_from_sql('familyid='.$fam->id.' order by birthday');
			if(@kids)
			{
				foreach my $kid (@kids)
				{
					$kid->{$_} = $kid->get($_) foreach $kid->columns;
				}
				$fam->{kids} = \@kids;
			}
			
			if($fam->last)
			{
				#print "$last	/	$fam->{first}\n";
				my $name = $fam->{first};
				$name .= ' & '.$fam->{spouse} if $fam->{spouse};
				$name .= ' '.$fam->{last};
			
		
				if($fam->{photo_num} != '?')
				{
					
					my $photo_file = $AppCore::Config::WWW_ROOT.'/mods/ThemePHC/dir_photos/thumbs/dsc_0'.$fam->{photo_num}.'.jpg';
					$fam->{large_photo} = $AppCore::Config::WWW_ROOT.'/mods/ThemePHC/dir_photos/dsc_0'.$fam->{photo_num}.'.jpg';
					#print STDERR "Primary photo: $photo_file\n";
					if(! -f $www_path.$photo_file)
					{
						$photo_file = $AppCore::Config::WWW_ROOT.'/mods/ThemePHC/dir_photos/thumbs/dsc_'.$fam->{photo_num}.'.jpg';
						$fam->{large_photo} = $AppCore::Config::WWW_ROOT.'/mods/ThemePHC/dir_photos/dsc_'.$fam->{photo_num}.'.jpg';
						#print STDERR "Setting secondary photo path: $photo_file (due to bad $www_path$photo_file)\n";
					}
					if(!-f $photo_file)
					{
						#print STDERR "No photo at: $photo_file\n";
						if($fam->{photo_num})
						{
							#my @test = `ls dir_photos/dsc_*$fam->{photo_num}.jpg`;
							#@test = `ls dir_photos/dsc_$fam->{photo_num}.jpg` if !@test;
							#print "$name:\tWarning: '$fam->{photo_num}' not found, possibilities:\n",
							#	join @test;
						}
						else
						{
							#print "No photo num at all: $name";
						}
					}
					
					$fam->{photo} = $photo_file;
					
					$fam->{comments} =~ s/([^\s]+\@[^\s]+\.\w+)/<a href='mailto:$1'>$1<\/a>/g;
				}
				else
				{
					#print "Missing Photo: $name\n";
				}
				
				#push @entries, \%entry;
				
				if($fam->{incomplete_flag})
				{
					#print "Info Sheet: $name\n";
				}
			}
		}
		
		return \@fams;
	};

};

package ThemePHC::Directory;
{
	# Inherit both the AppCore::Web::Module and Page Controller.
	# We use the Page::Controller to register a custom
	# page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	use Content::Page;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Family Directory','PHC Family Directory',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	#use DateTime;
	use AppCore::Common;
	#use JSON qw/to_json/;
	
	my $MGR_ACL = [qw/Pastor/];
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::Directory::Family
			PHC::Directory::Child
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		return $self;
	};
# 	
	# Implemented from Content::Page::Controller
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = $AppCore::Config::DISPATCHER_URL_PREFIX . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		#return $self->dispatch($req, $r);
		return $self->dir_page($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	our $DirectoryData;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
		$DirectoryData = [];
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	
	
	sub dir_page
	{
		my $self = shift;
		my ($req,$r) = @_;
		
		my $user = AppCore::Common->context->user;
		if(!$user || !$user->check_acl(['Can-See-Family-Directory']))
		{
			my $tmpl = $self->get_template('directory/denied.tmpl');
			return $r->output($tmpl);
		}
		
		#my $sub_page = shift @$path;
		my $sub_page = $req->next_path;
	
		if(!$DirectoryData)
		{
			print STDERR __PACKAGE__.": Cache miss, reloading data\n";
			$DirectoryData = PHC::Directory->load_directory();
		}
		
		my $dir_list = $DirectoryData; 
		
		my @directory = @{$dir_list || []};
		
		my $map_view = $req->{map} eq '1';
		
		my $tmpl = $self->get_template('directory/'.( $map_view? 'map.tmpl' : 'main.tmpl' ));
		
		my $start = $req->{start} || 0;
		
		$start =~ s/[^\d]//g;
		$start = 0 if !$start || $start<0;
		
		my $count = @directory;
		
		my $length = 15;
		$start = $count - $length if $start + $length > $count;
		
		@directory = @directory[$start .. $start+$count];
		
		$tmpl->param(count => $count);
		$tmpl->param(pages => int($count / $length));
		$tmpl->param(cur_page => int($start / $length) + 1);
		$tmpl->param(next_start => $start + $length);
		$tmpl->param(prev_start => $start - $length);
		$tmpl->param(is_end => $start + $length == $count);
		$tmpl->param(is_start => $start <= 0);
		
		#die Dumper \@directory;
		
		#@directory = grep { $_->{last} =~ /(Bryan)/ } @directory if $map_view;
		foreach my $entry (@directory)
		{
			###
		}
		$tmpl->param(entries => \@directory);
		
		
		#$r->output($tmpl);
		my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		return $r;
	}
	
	
}


1;