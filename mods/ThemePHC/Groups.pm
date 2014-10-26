use strict;

package PHC::Group;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		# Cheating a bit...
		table	=> AppCore::Config->get("PHC_GROUPS_DBTBL") || 'groups',
		
		schema	=> 
		[
			{ field => 'groupid',			type => 'int', @AppCore::DBI::PriKeyAttrs },
			{ field	=> 'managerid',			type => 'int',	linked => 'AppCore::User' },
			
			{ field => 'folder_name',		type => 'varchar(255)' },
			
			{ field => 'title',			type => 'varchar(255)' },
			{ field	=> 'tagline',			type => 'varchar(255)' },
			{ field	=> 'description',		type => 'varchar(255)' },
			
			{ field	=> 'group_type',		type => 'varchar(255)' },
			{ field	=> 'member_approval_required',	type => 'int(1)', null =>0, default =>0 },
			{ field	=> 'access_members_only',	type => 'int(1)', null =>0, default =>0 },
			{ field	=> 'listed_publicly',		type => 'int(1)', null =>0, default =>1 },
			
			{ field => 'contact_person',		type => 'varchar(255)' },
			{ field => 'contact_personid',		type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'phone',			type => 'varchar(255)' },
			{ field => 'email',			type => 'varchar(255)' },
			
			{ field => 'photo_file',		type => 'varchar(255)' },
			
			{ field	=> 'boardid',			type => 'int', linked => 'Boards::Board' },
			
			{ field => 'deleted',			type => 'int', null =>0, default=>0 },
			
			{ field => 'controller',		type => 'varchar(255)' },
		],	
	});
	
	#__PACKAGE__->has_many(members => 'PHC::Group::Member');
	__PACKAGE__->add_constructor(load_all => 'deleted!=1 and listed_publicly!=0 order by title');
	__PACKAGE__->add_constructor(search_like => '(title like ? or tagline like ? or description like ? or group_type like ? or contact_person like ?) and deleted!=1 and listed_publicly!=0 order by title');
	__PACKAGE__->add_constructor(search_like_group_type => '(group_type like ?) and deleted!=1 and listed_publicly!=0 order by title');
	
	sub members 
	{
		my $group = shift;
		return PHC::Group::Member->search(groupid => $group->id);
	}
	
	sub tmpl_select_list
	{
		my $pkg = shift;
		my $cur = shift;
		my $curid = ref $cur ? $cur->id : $cur;
		my $include_invalid = shift || 0;
		
		my @all = $pkg->retrieve_from_sql('1 order by title'); #`last`, `first`');
		my @list;
		if($include_invalid)
		{
			push @list, { 
				value 		=> undef,
				text		=> '(None)',
				selected	=> !$curid,
			};
		}
		my $max = 60;
		foreach my $item (@all)
		{
			my $title = substr($item->title,0,$max).(length($item->title) > $max ? '...':'');
			push @list, {
				value	=> $item->id,
				text	=> $title, #$item->last.', '.$item->first,
				#hint	=> $item->description,
				selected => defined $curid && $item->id == $curid,
			}
		}
		return \@list;
	}
	
	sub distinct_group_types
	{
		my $pkg = shift;
		my $cur = shift;
		my $sel_flag = shift || 0;
		
		my $distinct_sth = $pkg->db_Main->prepare_cached('select distinct group_type from '.$pkg->table.' where group_type<>"" and group_type is not null');
		$distinct_sth->execute;
		
		my @rows;
		my $max = 60;
		my $counter = 0;
		while(my $str = $distinct_sth->fetchrow)
		{
			if(!$sel_flag)
			{
				push @rows, $str;
				next;
			}
			
			my $title = substr($str,0,$max).(length($str) > $max ? '...':'');
			push @rows, {
				value	=> $str,
				text	=> $title,
				selected => defined $cur && $str eq $cur ? 1:0,
				counter => $counter ++,
			};
		}
		
		return \@rows;
	}
	
	sub is_admin
	{
		my $self = shift;
		my $user = shift;
		return 1 if $user == $self->contact_personid;
		return 1 if PHC::Group::Member->search(groupid => $self, userid=>$user, is_admin=>1);
		return 0; 
	}
	
};

package PHC::Group::Member;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta(
	{
		# Cheating a bit...
		@Boards::DbSetup::DbConfig,
		table	=> AppCore::Config->get("PHC_GROUP_MEMBERS_DBTBL") || 'group_members',
		
		schema	=> 
		[
			{ field => 'memberid',		type => 'int', @AppCore::DBI::PriKeyAttrs },
			{ field	=> 'groupid',		type => 'int',	linked => 'PHC::Group' },
			{ field	=> 'userid',		type => 'int',	linked => 'AppCore::User' },
			{ field => 'role',		type => 'varchar(255)' },
			
			{ field => 'is_admin',		type => 'int', null => 0, default=>0 },
			
			{ field => 'deleted',		type => 'int', null => 0, default=>0 },
		],	
	});
};


package ThemePHC::Groups;
{
	# Inherit both the AppCore::Web::Module and Page Controller.
	# We use the Page::Controller to register a custom
	# page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	use Content::Page;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Group Pages','PHC Group Pages',1,1,   # 1 = uses page path,  1 = uses content
		[
			{ field => 'group_folder',	type	=> 'string',#	linked		=> 'PHC::Group', 
				hint => 'Use either this field to set this page to a specific group, or the next field to show a list of groups for a specific type of group' },
			{ field => 'group_type',	type	=> 'string',#	list_method	=> 'PHC::Group->admin_option_list', default => '', 
				hint => 'Use this field to show a list of groups matching a specific group type, or the field above to show only a specific group.' }
		]);
	
	use Data::Dumper;
	#use DateTime;
	use AppCore::Common;
	use JSON qw/encode_json/;
	
	# For access to events associated with specific group
	use ThemePHC::Events;
	
	my $MGR_ACL = [qw/Pastor/];
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::Group
			PHC::Group::Member
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
		my $new_binpath = AppCore::Config->get("DISPATCHER_URL_PREFIX") . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		#return $self->dispatch($req, $r);
		return $self->main_page($req,$r,$page_obj);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	our %ControllerCache;
	our $GroupsListCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing cached data...\n";
		%ControllerCache = ();
		$GroupsListCache = {count=>0, cache=>{}};
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__,'prime_cache');
	
	sub prime_cache
	{
		my $self = shift;
		
		#print STDERR __PACKAGE__."->prime_cache: Loading ALL groups\n";
		$self->load_groups_list();
		
		#print STDERR __PACKAGE__."->prime_cache: Loading Small Groups\n";
		$self->load_groups_list({group_type=>'Small Group'});
		
		#print STDERR __PACKAGE__."->prime_cache: Loading Ministry Teams\n";
		$self->load_groups_list({group_type=>'Ministry Team'});
	}
	
	
	sub load_groups_list
	{
		my $class = shift;
		my $opts = shift || {};
		
		my $start = $opts->{start} || 0;
		my $search = $opts->{search} || '';
		my $length = $opts->{length} || 0;
		my $group_type = $opts->{group_type} || '';
		$group_type = 'Small Group' if lc $group_type eq 'small groups';
			
		
# 		use Data::Dumper;
# 		die Dumper $opts;
		
		my $cache_key = 'all';
		
		my $count = 0;
		if($group_type)
		{
			$cache_key = 'group_type:'.$group_type;
			$cache_key .= '/search:'.$search if $search;
				
		}
		elsif($search && length($search) > 0)
		{
			$cache_key = 'search:'.$search;
		}
		elsif($length > 0)
		{
			$count = $GroupsListCache->{count};
			if(!$count)
			{
				my $sth = PHC::Group->db_Main->prepare('select count(groupid) from '.PHC::Group->table.' where deleted!=1');
				$sth->execute();
				$count = $sth->fetchrow;
				$GroupsListCache->{count} = $count;
			}
				
			$length = $count - $start if $start + $length > $count;
			
			$start  += 0; # force cast to numbers
			$length += 0; # force cast to numbers
			
			$cache_key = join '', $start, $length;
		}
		
		if($GroupsListCache->{cache}->{$cache_key})
		{
			#print STDERR "load_directory: Cache HIT for key '$cache_key'\n";
			return $GroupsListCache->{cache}->{$cache_key};
		} 
			
		#print STDERR "load_groups_list: Cache miss for key '$cache_key'\n";
		
			
 		my $www_path = AppCore::Config->get('WWW_DOC_ROOT');
		
		my @fams;
		if($search)
		{
			my $like = '%'.$search.'%';
			@fams = PHC::Group->search_like($like,$like,$like,$like,$like);
			
			if($group_type)
			{
				@fams = grep { index($_->group_type,$group_type) > -1 } @fams;
			}
		}
		elsif($group_type)
		{
			@fams = PHC::Group->search_like_group_type('%'.$group_type.'%');
			#die Dumper \@fams;
		}
		else
		{
			@fams = PHC::Group->retrieve_from_sql('deleted!=1 and listed_publicly!=0 order by title '.($length>0 ? 'limit '.$start.', '.$length : ''));
		}
		
		my @output_list;
		foreach my $fam_obj (@fams)
		{
			my $fam = {};
			$fam->{$_} = $fam_obj->get($_)."" foreach $fam_obj->columns;
			
			my @kids = PHC::Group::Member->retrieve_from_sql('groupid='.$fam_obj->id); 
			if(@kids)
			{
				my @kid_list;
				foreach my $kid_obj (@kids)
				{
					my $kid = {};
					$kid->{$_} = $kid_obj->get($_)."" foreach $kid_obj->columns;
					push @kid_list, $kid;
				}
				$fam->{members} = \@kid_list;
			}
			else
			{
				$fam->{members} = [];
			}
			
			push @output_list, $fam;
		}
		
# 		my $result = \@output_list;
# 		if($length > 0)
# 		{
			my $result = 
			{
				count	=> $count ? $count : scalar @output_list,
				list	=> \@output_list, 
				start	=> $start,
				length	=> $length ? $length : scalar @output_list,
				search	=> $search,
			};
#		}
		
		#use Data::Dumper;
		#die Dumper $result;
		$GroupsListCache->{cache}->{$cache_key} = $result;
		
		return $result;
	};
	
	sub get_group_controller
	{
		my $self = shift;
		my $group = shift;
		
		return $ControllerCache{$group->id} if $ControllerCache{$group->id};
		
		my $controller = undef;
		
		#die $group->folder_name;
		if($group->controller)
		{
			#eval 'use '.$group->forum_controller;
			#die $@ if $@ && $@ !~ /Can't locate/;
			
			$controller = AppCore::Web::Module->bootstrap($group->controller);
			$controller->binpath($self->binpath);
		}
		
		
		$ControllerCache{$group->id} = $controller;
		
		return $controller;
	}
	
	sub can_edit_group
	{
		my $self = shift;
		my $group = shift;
		my $user = AppCore::Common->context->user;
		my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
		my $can_edit = $admin || $group->managerid == $user;
		if(!$can_edit && $user)
		{
			my $mem = PHC::Group::Member->by_field(userid => $user, groupid => $group);
			$can_edit = 1 if $mem && $mem->is_admin;
		}
		return $can_edit;
	}
	
	sub main_page
	{
		my $self = shift;
		my ($req,$r,$page_obj) = @_;
		
 		my $user = AppCore::Common->context->user;
 		
 		if($page_obj)
 		{
 			my $folder = $page_obj->get_extended_data->{group_folder};
 			if($folder)
 			{
				
				my $group = PHC::Group->by_field(folder_name => $folder);
				return $r->error("No Such Group","Sorry, the group specified doesn't exist!") if !$group;
				
				#$req->push_page_path($req->shift_path);
				
				return $self->group_page($req,$r,$group);
			}
 		}
		
		#my $sub_page = shift @$path;
		my $sub_page = $req->next_path;
		if($sub_page eq 'delete')
		{
			AppCore::AuthUtil->require_auth($MGR_ACL);
			
			my $fam = $req->groupid;
			
			my $group = PHC::Group->retrieve($fam);
			return $r->error("No Such Group","Sorry, the group ID you gave does not exist") if !$group;
			
			$group->deleted(1);
			$group->update;
			
			return $r->redirect($self->binpath);
		}
		elsif($sub_page eq 'delete_member')
		{
			my $mbr = PHC::Group::Member->retrieve($req->memberid);
			return $r->error("No Such Member","Sorry, the member ID you gave does not exist") if !$mbr;
			
			my $group = $mbr->groupid;
			return $r->error("Invalid Member","Member ID not associated with any group") if !$group || !$group->id;
			
			return $r->error("Permission Denied","Sorry, you don't have permission to edit this group") if !$self->can_edit_group($group);
			
			$mbr->delete;
			
			return $r->redirect($self->binpath.'/edit?groupid='.$group->id.'#members');
		}
		elsif($sub_page eq 'edit')
		{
			my $fam = $req->groupid;
			
			my $group = PHC::Group->retrieve($fam);
			return $r->error("No Such Group","Sorry, the group ID you gave does not exist") if !$group;
			return $r->error("Permission Denied","Sorry, you don't have permission to edit this group") if !$self->can_edit_group($group);
			
			my $tmpl = $self->get_template('groups/edit.tmpl');
			
			$tmpl->param($_ => $group->get($_)) foreach $group->columns;
			
			my $del_url_base = $self->module_url('delete_member?memberid=');
			
			my @members = PHC::Group::Member->search(groupid => $group->id);
			my $count = 0;
			foreach my $mbr (@members)
			{
				$mbr->{$_} = $mbr->get($_) foreach $mbr->columns;
				$mbr->{member_name} = $mbr->userid->display if $mbr->userid;
				$mbr->{odd_flag} = ++ $count % 2 == 0;
				$mbr->{delete_url} = $del_url_base.$mbr->id;
			}
			$tmpl->param(members => \@members);
			
			$tmpl->param(group_types => PHC::Group->distinct_group_types($group->group_type,1)); # 1 = return in a 'tmpl_select_list' format
			
			# Not worrying about admin because user must be an "amin of this group" to edit
			#my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			#$tmpl->param(is_admin => $admin);
			
			$tmpl->param(manager_list => AppCore::User->tmpl_select_list($group->managerid,1));
			$tmpl->param(new_members  => AppCore::User->tmpl_select_list(undef,1));
			#$tmpl->param(spouse_users => AppCore::User->tmpl_select_list($group->spouse_userid,1));
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Edit Group',$self->module_url('edit?groupid='.$fam),0);
			$view->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'new')
		{
			AppCore::AuthUtil->require_auth($MGR_ACL);
			
			my $tmpl = $self->get_template('groups/edit.tmpl');
			
			my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			$tmpl->param(is_admin => $admin);
			
			$tmpl->param(group_types  => PHC::Group->distinct_group_types(undef,1)); # 1 = return in a 'tmpl_select_list' format
			$tmpl->param(manager_list => AppCore::User->tmpl_select_list(undef,1));
			$tmpl->param(new_members  => AppCore::User->tmpl_select_list(undef,1));
			$tmpl->param(listed_publicly => 1);
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('New Group',$self->module_url('new'),0);
			$view->output($tmpl);
			return $r;
			
		}
		elsif($sub_page eq 'post')
		{
			my $fam = $req->groupid;
			
			my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			
			my $group = PHC::Group->retrieve($fam);
			if(!$group)
			{
				# Only insert new group if Admin test passes
				if($admin)
				{
					$group = PHC::Group->insert({ title => $req->title });
					print STDERR "Debug: Created new group ID $group\n";
				}
				else
				{
					return $r->error("No Such Group","Sorry, the group ID you gave does not exist") if !$group;
				} 
			}
			
			my $can_edit = $admin || $group->managerid == $user;
			if(!$can_edit && $user)
			{
				my $mem = PHC::Group::Member->by_field(userid => $user, groupid => $group);
				$can_edit = 1 if $mem && $mem->is_admin;
			}
			
			return $r->error("Permission Denied","Sorry, you don't have permission to edit this group") if !$can_edit;
			
			if($req->group_type eq '_')
			{
				$req->{group_type} = $req->{group_type_new};
			}
			
			# Anyone can edit these columns (anyone, well, anyone who has permission)
			my @cols = qw/
				title
				tagline
				description
				contact_person
				contact_personid
				phone
				email
			/;

			die "You must give a title" if !$req->{title};
			
			if(!$req->{folder})
			{
				my $folder = Boards->to_folder_name($req->{title});
				$folder =~ s/(^\s+|\s+$)//g;
				$folder .= '_'.$group->id if PHC::Group->by_field(folder_name => $folder);
				$req->{folder} = $folder;
			}
			
			# Add in admin-only columns
			if($admin)
			{
				push @cols, qw/managerid member_approval_required access_members_only listed_publicly group_type/;
			}
			
			# Update data fields
			foreach my $col (@cols)
			{
				#print STDERR "Checking col: $col ($req->{$col})\n";
				$group->set($col, $req->{$col}) if defined $req->{$col};
			}
			
			# Automatically fill in contact name/phone/email based on managerid if necessary
			if($group->managerid && 
				(!$group->contact_person || 
				 !$group->contact_personid ||
				 !$group->contact_personid->id ||
				 !$group->phone || 
				 !$group->email))
			{
				$group->contact_person($group->managerid->display) if !$group->contact_person;
				if($group->email && (!$group->contact_personid || !$group->contact_personid->id))
				{
					$group->contact_personid(AppCore::User->by_field(email => $group->email));
				}
				$group->contact_personid($group->managerid) if !$group->contact_personid || !$group->contact_personid->id;
				$group->email($group->contact_personid->email) if !$group->email;
				$group->phone($group->contact_personid->phone) if !$group->phone;
			}
			
			
# 			use Data::Dumper;
# 			print STDERR "Data dump:\n";
# 			print STDERR Dumper $group;
			
 			$group->update;
			
			# Update existing kids names/bdays
			my @members = PHC::Group::Member->search(groupid => $group->id);
			if(@members)
			{
				foreach my $mbr (@members)
				{
					my $name = $req->{'role_'.$mbr->id};
					$mbr->role($name) if $mbr->role ne $name;
					
					my $is_admin = $req->{'admin_'.$mbr->id};
					$mbr->is_admin($is_admin) if $mbr->is_admin ne $is_admin;
					
					$mbr->update if $mbr->is_changed;
				}
			}
			
			# Add new child if needed
			if($req->{new_member_userid})
			{
				print STDERR "Debug: Adding new member: '$req->{name_new}'\n";
				my $args = {
					groupid		=> $group->id,
					userid		=> $req->{new_member_userid},
					role		=> $req->{role_new},
					is_admin	=> $req->{admin_new} ? 1:0,
				};
				print STDERR "New member data: ".Dumper($args);
				PHC::Group::Member->insert($args); 
			}
			
			if(!$group->boardid || !$group->boardid->id)
			{
				my $boards_group = Boards::Group->find_or_create({ title=> 'PHC Groups' }); 
				my $board = Boards::Board->create({
					groupid 	=> $boards_group->id, 
					managerid	=> $group->managerid,
					folder_name	=> $group->folder_name,
					title		=> $group->title,
				});
				
				$group->boardid($board);
				$group->update;
				print STDERR "Groups: Created new group board: boardid $board for group '". $group->title. "'\n";
			}
			else
			{
				my $board = $group->boardid;
				foreach (qw/managerid folder_name title/)
				{
					$board->set($_, $group->get($_))
						     if $board->get($_) ne
							$group->get($_);
				}
				$board->update if $board->is_changed;
			}
			
			if($req->output_fmt eq 'json')
			{
				return $r->output_data("application/json", '{saved:true}'); 
				#return $r->output_data("text/plain", $json);
			}
			
			if($req->{add_another})
			{
				return $r->redirect($self->binpath.'/edit?groupid='.$group->id.'#add_another');
			}
			else
			{
				return $r->redirect($self->binpath.'/'.$group->folder_name);
			}
			
		}
		elsif($sub_page)
		{
			my $group = PHC::Group->by_field(folder_name => $sub_page);
			return $r->error("No Such Group","Sorry, the group specified doesn't exist!") if !$group;
			
			$req->push_page_path($req->shift_path);
			
			return $self->group_page($req,$r,$group);
		}
		else
		{
			my $map_view = $req->{map} eq '1'; # TODO is map view even relevant to groups?
			
			my $tmpl = $self->get_template('groups/'.( $map_view? 'map.tmpl' : 'main.tmpl' ));
			
			my $start = $req->{start} || 0;
			
			$start =~ s/[^\d]//g;
			$start = 0 if !$start || $start<0;
			
			my $length = 50;
			
			if($req->{search} && $req->output_fmt ne 'json')
			{
				# Require at least 3 letters if not using json
				return $r->error("At least 3 letters","You need at least 3 letters to search") if length $req->{search} < 3;
			}
			
			#@directory = @directory[$start .. $start+$count];
			my $opts = {};
			if($page_obj)
			{
				$opts->{group_type} = $page_obj->get_extended_data->{group_type}; 
			}
			
			if($req->{search})
			{
				$opts->{search} = $req->{search};
			}
			else
			{
				$opts->{start} = $start;
				$opts->{length} = $length;
			}
			
			my $directory_data = $self->load_groups_list($opts);
			
# 			my $my_entry;
# 			if($user)
# 			{
# 				$my_entry = PHC::Group->by_field(userid => $user);
# 				$my_entry = PHC::Group->by_field(spouse_userid => $user) if !$my_entry;
# 			}
			#$my_entry = 0;
			my @directory = @{$directory_data->{list}};
			my $bin = $self->binpath;
			#@directory = grep { $_->{last} =~ /(Bryan)/ } @directory if $map_view;
			my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			my $userid = $user ? $user->id : undef;
			my $mobile = AppCore::Common->context->mobile_flag;
			foreach my $group (@directory)
			{
				# TODO editing flags for non-global-admins
				$group->{can_edit} = $admin; ## || ($userid && ($group->{userid} == $userid || $group->{spouse_userid} == $userid));
				# TODO membership flags
				#$group->{has_account} = $my_entry ? 1:0; # relevant only if !can_edit
				$group->{is_admin} = $admin;
				$group->{bin} = $bin;
				$group->{is_mobile} = $mobile;
			}
			
			#use Data::Dumper;
			#die Dumper $directory_data;
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($directory_data);
				return $r->output_data("application/json", $json); # if $req->output_fmt eq 'json';
				#return $r->output_data("text/plain", $json);
			}
			
			my $count = $directory_data->{count};
			$start = $directory_data->{start};
			$length = $directory_data->{length};
			$length = 1 if !$length;
			
			$tmpl->param(count	=> $count);
# 			$tmpl->param(pages	=> int($count / $length));
# 			$tmpl->param(cur_page	=> int($start / $length) + 1);
# 			$tmpl->param(next_start	=> $start + $length);
# 			$tmpl->param(prev_start	=> $start - $length);
# 			$tmpl->param(is_end	=> $start + $length >= $count);
# 			$tmpl->param(is_start	=> $start <= 0);
# 			$tmpl->param(start	=> $start);
# 			$tmpl->param(length	=> $length);
# 			$tmpl->param(next_idx	=> $start + $length);
			$tmpl->param(search	=> $req->{search});
			$tmpl->param(is_admin	=> $admin);
			
			#die Dumper \@directory;
			
			$tmpl->param(entries => \@directory);
# 			use Data::Dumper;
# 			die Dumper \@directory;

			if($page_obj)
			{
				$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
			}
			
			#$r->output($tmpl);
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
	}
	
	sub group_page
	{
		my $self = shift;
		my ($req,$r,$group) = @_;
		
		if($group->access_members_only)
		{
			AppCore::AuthUtil->require_auth;
			my $user = AppCore::Common->context->user;
			my $mem = PHC::Group::Member->by_field(userid => $user, groupid => $group);
			return $r->error("Access Restricted","Sorry, but the administrator limited access to this group to only members. Sorry!") if !$mem;
		}
		
		# Here we attempt to check to see if there is a Content::Page that lists our 'Group Type' -
		# if there is, and we were NOT accessed thru that page (e.g. current URL does not start with that page's URL)
		# then redirect to that page, appended with our group folder.
		# This would happen if someone prepends our folder name to another page that doesn't list our group type or lists all groups
		Content::Page->add_constructor(search_group_type => 'extended_data like ?') if !Content::Page->can('search_group_type');
		my @search = Content::Page->search_group_type('%group_type":"%'.$group->group_type.'%"%');
		if(my $page = shift @search)
		{
			my $url = $page->url;
			# Note != to detect if it DOESN'T start with the page url
			if(index($req->page_path,$url) != 0)
			{
				return $r->redirect("$url/". $group->folder_name);
			}
		}
		
		
		my $user = AppCore::Common->context->user;
		my $sub_page = $req->next_path;
		
		my $post = $sub_page ? Boards::Post->retrieve($sub_page) || Boards::Post->by_field(folder_name => $sub_page) : 0;
		#print STDERR __PACKAGE__."::group_page: sub_page:'$sub_page', post: $post\n";
		
		if($sub_page eq 'new_event' || $sub_page eq 'post_event' || $sub_page eq 'edit_event')
		{
			# TODO wrap these actions and make event handlers for these actions
		}
		elsif($sub_page eq 'new' || $sub_page eq 'post' || $sub_page eq 'edit' || $sub_page eq 'upload_photo' || $post)
		{
			# Board actions - TODO test and see if more actiosn need to be routed
			$self->SUPER::board_page($req,$r,$group->boardid);
		}
		elsif($sub_page eq 'admin_notify')
		{
			my $post = Boards::Post->by_field(folder_name => $req->post);
			
			return $r->error("Unknown Post","Sorry, invalid post") if !$post;
			
			# Email everyone in this group
			$self->send_email_notifications($post);
			
			# Post to talk page and FB 
			my $tp = $self->send_talk_notifications($post);
			
			my $tp_url = ""; #"http://beta.mypleasanthillchurch.org/connect/talk/".$tp->folder_name;
			return $r->output_data("text/html","Notifications sent for post $post, title: ".$post->subject.", talk post url: <a href='$tp_url'>$tp_url</a>");
		}
		else
		{
			my $tmpl = $self->get_template('groups/group_page.tmpl');
			
			# Load posts
			my $data = $self->load_post_list($group->boardid, $req);
			if($req->output_fmt eq 'json')
			{
				# http://beta.mypleasanthillchurch.org/connect/groups/?first_ts=2011-07-15+11%3A09%3A30&output_fmt=json&mode=poll_new_posts
				my $json = encode_json($data);
				return $r->output_data("application/json", $json);
				#return $r->output_data("text/plain", $json);
			}
			
			#die Dumper $group;
			my $controller = $self->get_group_controller($group);
			if($controller)
			{
				my ($output,$is_full_page) = $controller->group_page_hook($self,$req,$r,$group,$data,$tmpl);
				
				return $output if $is_full_page;
				$tmpl = $output;
			}
			
			$self->setup_group_page_template($tmpl,$group,$data);
			
			# Output
			my $view = Content::Page::Controller->get_view('sub',$r);
			#$view->breadcrumb_list->push('Groups Home',$self->module_url(),0);
			$view->breadcrumb_list->push($group->title,$self->module_url($group->folder_name),0);
			$view->output($tmpl);
			return $r;
		}
	}
	
	sub setup_group_page_template
	{
		my $self = shift;
		my $tmpl = shift;
		my $group = shift;
		my $data = shift;
		
		$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
		
		my @members = $group->members;
		my @mcols = PHC::Group::Member->columns;
		foreach my $mem (@members)
		{
			$mem->{$_} = $mem->get($_) foreach @mcols;
			$mem->{display} = $mem->userid->display;
			$mem->{photo} = PHC::Directory->photo_for_user($mem->userid);
		}
		$tmpl->param(group_members => \@members);
			
		my $board = $group->boardid;
		$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
		$tmpl->param('posts_'.$_ => $data->{$_}) foreach keys %$data;
		$tmpl->param($_ => $data->{$_}) foreach keys %$data; # since we are using Board's list.tmpl, they expect the params with now prefix
		$tmpl->param(boards_indent_multiplier => $Boards::INDENT_MULTIPLIER);
		my $tmpl_incs = $self->config->{tmpl_incs} || {};
		#use Data::Dumper;
		#die Dumper $tmpl_incs;
		foreach my $key (keys %$tmpl_incs)
		{
			$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
		}
		
		$tmpl->param(boards_list_as_widget => 1);
		
		# Since a theme has the option to inline a new post form in the post template,
		# provide the controller a method to hook into the template variables from here as well
		$self->new_post_hook($tmpl,$board);
		
		my $user = AppCore::Web::Common->context->user;
		my $can_admin = 1 if $user && ($user->check_acl(['Pastor']) || $group->is_admin($user)); 
		$tmpl->param(has_alt_postas => $can_admin);
		if($can_admin)
		{
			$tmpl->param(alt_postas_name  => $group->title); #'Pleasant Hill Church');
			$tmpl->param(alt_postas_email => 'webmaster@mypleasanthillchurch.org');
			$tmpl->param(alt_postas_photo => '/appcore/mods/User/user_photos/fbb55eae25485996cd31b362d9296591f6.jpg');
		}
	
		#die Dumper $data;
		
		# Note forced stringification required below.
		$tmpl->param('posts_approx_time' => ''.approx_time_ago($data->{first_ts}));
		
		# For videos linked in posts...
		$self->apply_video_providers($tmpl);
	
		# Load events
		$self->{event_controller} = AppCore::Web::Module->bootstrap('ThemePHC::Events') if !$self->{event_controller};
		my $event_controller = $self->{event_controller};
		
		my $events_data = $event_controller->load_basic_events_data($group);
	
		#die Dumper $events_data;
		$tmpl->param(events_weekly => $events_data->{weekly});
		$tmpl->param(events_dated  => $events_data->{dated});
		
		# Add contact photo
		use ThemePHC::Directory;
		my $photo = PHC::Directory->photo_for_user($group->contact_personid);
		$tmpl->param(contact_photo => $photo);
	}
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;
		my $user = shift;
		
# 		my $cmt = $req->{comment};
# 		
# 		
# 		$cmt =~ s/(^\s+|\s+$)//g;
# 		$cmt =~ s/(^&nbsp;)//g;
# 		$cmt =~ s/<p>&nbsp;/<p>/g;
# 		$cmt =~ s/<p>&nbsp;<\/p>//g;
# 		$cmt =~ s/^\s*\n+//sg;
# 		$cmt =~ s/(^\t+|\t+$)//g;
# 
# 		#die Dumper $cmt if $cmt =~ /^\s*\n/;
# 		#die Dumper $cmt;
# 		#die "Test done";
# 		
# 		$req->{comment} = $cmt;
# 		
# # 		open(TMP,">/tmp/test.txt");
# # 		print TMP $cmt;
# # 		close(TMP); 
# # 		
# 		#die "Test done";
# 		
# 		delete $req->{plain_text};
# 		$req->{no_html_conversion} = 1;
# 		
# 		my $can_post = ($_ = AppCore::Web::Common->context->user) && $_->check_acl($PASTOR_ACL);
# 		die "Unauthorized - sorry, you can't post in this blog" if !$can_post;
		
		
		# Rely on superclass to do the actual post creation
		my $post = $self->SUPER::create_new_thread($board, $req, $user);
		
		# Flag as a 'post' not just a 'small update' 
		$post->post_class('post');
		$post->update;
		
# 		open(TMP,">/tmp/test2.txt");
# 		print TMP $post->text;
# 		close(TMP);
# 		
		# Email everyone in this group
		$self->send_email_notifications($post);
		
		# Post to talk page and FB 
# 		my $user = AppCore::Web::Common->context->user;
# 		my $can_admin = 1 if $user && ($user->check_acl(['Pastor']) || $group->is_admin($user));
# 		if($can_admin)
# 		{
			$self->send_talk_notifications($post);
		#}
		
		return $post;
	}
	
	sub group_for_post
	{
		my $self = shift;
		my $post = shift;
		my $board = $post->boardid;
		my $group = PHC::Group->by_field(boardid => $board->id);
		return $group;
	}
	
	sub send_email_notifications
	{
		my $self = shift;
		my $post = shift;

		#return;
		
		my $group = $self->group_for_post($post);
		
		print STDERR __PACKAGE__."::send_email_notifications for new post: ".$post->subject."\n";
		
		my @members = $group->members;
		
		my @users = grep { $_->email } map { $_->userid } @members;
		
		#my @users = AppCore::User->retrieve_from_sql('email <> ""'); # and allow_email_flag!=0');
		#my @users = AppCore::User->retrieve_from_sql('email like "josiah%" or email like "jbryan%"'); # and allow_email_flag!=0');
		
		
		my $subject = "[PHC] New Post in ".$group->title.": ".$post->subject; # the subject was set correctly in create_new_thread()
		#my $body = AppCore::Web::Common->html2text($post->text);
		#$body =~ s/\n\s*$//g;
		
		my $folder = $post->folder_name;
		
		#my $server = AppCore::Config->get('WEBSITE_SERVER');
		
		my $email_body = "\n"
				.$post->posted_by->display." has added a new post to the bulletin board for group \"".$group->title."\" at MyPleasantHillChurch.org.\n"
				."\n"
				."Read \"".$post->subject."\" here:\n"
				."    ".$self->module_url($group->folder_name,1)."/$folder\n"
				."\n"
				."Thanks,\n"
				."The PHC Website Robot";
		
		print STDERR "Body text:".$email_body;
		
		my %seen_email = ();
		foreach my $user (@users)
		{
# 			if(! $PREF_EMAIL_NEW_POST->value($user) )
# 			{
# 				print STDERR "Not emailing ".$user->email." due to negative preference on prefid ".$PREF_EMAIL_NEW_POST." for userid $user\n";
# 				next;
# 			}
			
			#my $subj = "Pastor Bryan Added a New Post in the Pastor's Blog";
			my $text = "Hi ".$user->display.",\n".$email_body;
			
			#print STDERR "Emailing user ".$user->display." at ".$user->email."\n";
				
			if(!$seen_email{$user->email})
			{
				#$user = AppCore::User->retrieve(1);
				#PHC::Web::Common->send_email([$user->email], $subj, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
				my $msgid = AppCore::EmailQueue->send_email([$user->email], $subject, $text);
				
				print STDERR "Queued msgid $msgid ".$user->email."\n"; #Subject: $subj\n$text\n";
				
				$seen_email{$user->email} = 1;
			}
		}
		
		#AppCore::Web::Common->send_email(\@emails, $subject, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
	}
	
	sub send_talk_notifications
	{
		my $self = shift;
		my $post = shift;
		
		my $group = $self->group_for_post($post);

		# Mom doesnt want notifications going out for misfits on the talk page
		return if $group->folder_name eq 'misfits';
		
		
		my $folder = $post->folder_name;
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		#my $post_url = "${server}/learn/pastors_blog/$folder";
		my $post_url = $self->module_url($group->folder_name,1)."/$folder";
		
		my $data = {
			poster_name	=> 'PHC Website',
			poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
			poster_email	=> 'josiahbryan@gmail.com',
			comment		=> $post->posted_by->display." has added a new post, \"".$post->subject."\" to the bulletin board for group \"".$group->title."\". Read it at: $post_url",
			subject		=> "New Post in ".$group->title.": '".$post->subject."'", 
		};
		
		my $talk_board_controller = AppCore::Web::Module->bootstrap('ThemePHC::BoardsTalk');
		my $talk_board = Boards::Board->retrieve(1); # id 1 is the prayer/praise/talk board
		
		my $talk_post = $talk_board_controller->create_new_thread($talk_board,$data);
		
		# Add extra data internally
		$talk_post->data->set('blog_postid',$post->id);
		$talk_post->data->set('post_url',$post_url);
		$talk_post->data->set('title',$post->subject);
		$talk_post->data->update;
		$talk_post->update;
		$talk_post->{_orig} = $post;
		
		# Note: We call send_notifcations() on $self so it will call our facebook_notify_hook()
		#       to reformat the FB story args the way we want them before uploading instead 
		#       of using the default story format.
		#     - We 'really_upload' so we can use $self (because we want to call our facebook_notify_hook())
		#     - Give the $talk_board in the args because the FB notification routine needs the
		#       FB wall ID and sync info from the board - and its not set on the Pastor's Blog board
		my @errors = $self->send_notifications('new_post',$talk_post,{really_upload=>1, board=>$talk_board}); # Force the FB method to upload now rather than wait for the poller crontab script
		if(@errors)
		{
			print STDERR "Error sending notifications of new blog post $post: \n\t".join("\n\t",@errors)."\n";
		}
		
		return $talk_post;
			
	}
	
	sub facebook_notify_hook
	{
		my $self = shift;
		my $post = shift;
		my $form = shift;
		my $args = shift;
		
		# Create the body of the FB post
		my $post_url = $post->data->get('post_url');
		
		$form->{message} = $post->text; 
		#"New video from PHC: ".$post->data->get('description').". Watch it now at ".LWP::Simple::get("http://tinyurl.com/api-create.php?url=${phc_video_url}");
		 
		# Set the URL for the link attachment
		$form->{link} = $post_url;
		
		#my $image = $self->video_thumbnail($post);
		
		#my $pastor_user = AppCore::User->by_field(email => 'pastor@mypleasanthillchurch.org');
		
		my $orig_post = $post->{_orig};
		my $quote;
		if(!$orig_post)
		{
			$quote = "Read the full post at ".$post_url;
		}
		else
		{
			our $SHORT_TEXT_LENGTH = 60;
			my $short_len = AppCore::Config->get("BOARDS_SHORT_TEXT_LENGTH")     || $SHORT_TEXT_LENGTH;
			my $short = AppCore::Web::Common->html2text($orig_post->text);
			
			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
			
			$quote = "\"".
				 substr($short,0,$short_len) . "\"" .
				(length($short) > $short_len ? '...' : '');
		}
		
		my $image = 'http://cdn1.mypleasanthillchurch.org/appcore/mods/User/user_photos/fbb55eae25485996cd31b362d9296591f6.jpg'; # PHC Logo in white square
		
		# Finish setting link attachment attributes for the FB post
		$form->{picture}	= $image; # ? $image : 'https://graph.facebook.com/180929095286122/picture';
		$form->{name}		= $post->data->get('title');
		$form->{caption}	= "by ".$post->posted_by->display;
		$form->{description}	= $quote; 
		#$post->data->get('description');
		
		# Update original post with attachment data
		my $d = $post->data;
		$d->set('has_attach',1);
		$d->set('name', $form->{name});
		$d->set('caption', $form->{caption});
		$d->set('description', $form->{description});
		$d->set('picture', $form->{picture});
		$d->update;
		$post->post_class('link');
		$post->update;
		
		# Replace the default Boards FB action with a link to the video post
		$form->{actions} = qq|{"name": "View at PHC's Site", "link": "$post_url"}|;
		
		# 
		
		# We're working with a hashref here, so no need to return anything, but we will anyway for good practice
		return $form;
	}
}

package ThemePHC::Group::Controller::Physh;
{
	use base qw/AppCore::Web::Module/;
	sub group_page_hook 
	{
# 		use Data::Dumper;
# 		die Dumper \@_;
		my $self = shift;
		my $main_controller = shift;
		my $req = shift;
		my $r = shift;
		my $group = shift;
		my $board_data = shift;
		my $tmpl = shift;
		
		#my ($output,$is_full_page) = $controller->group_page_hook($req,$r,$group,$data,$tmpl);
		
		$tmpl = $main_controller->get_template('groups/physh-main.tmpl');
		
		$main_controller->setup_group_page_template($tmpl,$group,$board_data);
		
# 		# Output
# 		my $view = Content::Page::Controller->get_view('sub',$r);
# 		#$view->breadcrumb_list->push('Groups Home',$self->module_url(),0);
# 		$view->breadcrumb_list->push($group->title,$self->module_url('/'.$group->folder_name),0);
# 		$view->output($tmpl);
# 		return $r;
		
		return wantarray ? ($tmpl,0) : $tmpl; # 1 = full page
	}
};


1;

