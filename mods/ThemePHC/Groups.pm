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
	
	__PACKAGE__->has_many(members => 'PHC::Group::Member');
	__PACKAGE__->add_constructor(load_all => 'deleted!=1 and listed_publicly!=0 order by group_type, title');
	__PACKAGE__->add_constructor(search_like => '(title like ? or tagline like ? or description like ? or group_type like ? or contact_person like ?) and deleted!=1 and listed_publicly!=0 order by group_type, title');
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
			{ field	=> 'groupid',		type => 'int',	linked => 'PHC::Group' },
			{ field => 'memberid',		type => 'int', @AppCore::DBI::PriKeyAttrs },
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
	__PACKAGE__->register_controller('PHC Group Pages','PHC Group Pages',1,1);  # 1 = uses page path,  1 = doesnt use content
	
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
		return $self->main_page($req,$r);
		
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
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	
	sub load_groups_list
	{
		my $class = shift;
		my $start = shift || 0;
		my $search;
		my $length;
		if($start && !@_)
		{
			# One arg = assume first arg is a search string
			$search = $start;
			$start = 0;
			$length = 0;
		}
		else
		{
			$search = '';
			$length = shift; 
		}
		
		
		my $cache_key = 'all';
		
		my $count = 0;
		if($length > 0)
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
		elsif($search && length($search) > 0)
		{
			$cache_key = 'search:'.$search;
		}
		
		if($GroupsListCache->{cache}->{$cache_key})
		{
			#print STDERR "load_directory: Cache HIT for key '$cache_key'\n";
			return $GroupsListCache->{cache}->{$cache_key};
		} 
			
		#print STDERR "load_directory: Cache miss for key '$cache_key'\n";
		
			
		my $www_path = AppCore::Config->get("WWW_DOC_ROOT");
		
		my @fams;
		if($search)
		{
			my $like = '%'.$search.'%';
			@fams = PHC::Group->search_like($like,$like,$like,$like,$like);
		}
		else
		{
			@fams = PHC::Group->retrieve_from_sql('deleted!=1 and listed_publicly!=0 order by group_type, title '.($length>0 ? 'limit '.$start.', '.$length : ''));
		}
		
		my @output_list;
		foreach my $fam_obj (@fams)
		{
			my $fam = {};
			$fam->{$_} = $fam_obj->get($_)."" foreach $fam_obj->columns;
			
			my @kids = PHC::Group::Member->retrieve_from_sql('groupid='.$fam_obj->id); #.' order by birthday');
			if(@kids)
			{
				my @kid_list;
				foreach my $kid_obj (@kids)
				{
					my $kid = {};
					$kid->{$_} = $kid_obj->get($_)."" foreach $kid_obj->columns;
					push @kid_list, $kid;
				}
				$fam->{kids} = \@kid_list;
			}
			else
			{
				$fam->{kids} = [];
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
	
	sub get_controller
	{
		my $self = shift;
		my $group = shift;
		
		return $ControllerCache{$group->id} if $ControllerCache{$group->id};
		
		my $controller = $self;
		
		#die $group->folder_name;
		if($group->forum_controller)
		{
			#eval 'use '.$group->forum_controller;
			#die $@ if $@ && $@ !~ /Can't locate/;
			
			$controller = AppCore::Web::Module->bootstrap($group->forum_controller);
			$controller->binpath($self->binpath);
		}
		
		
		$ControllerCache{$group->id} = $controller;
		
		return $controller;
	}
	
	sub main_page
	{
		my $self = shift;
		my ($req,$r) = @_;
		
 		my $user = AppCore::Common->context->user;
		
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
		elsif($sub_page eq 'edit')
		{
			my $fam = $req->groupid;
			
			my $user = AppCore::Common->context->user;
			
			my $group = PHC::Group->retrieve($fam);
			return $r->error("No Such Group","Sorry, the group ID you gave does not exist") if !$group;
			
			my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			my $can_edit = $admin || $group->managerid == $user;
			if(!$can_edit && $user)
			{
				my $mem = PHC::Group::Member->by_field(userid => $user, groupid => $group);
				$can_edit = 1 if $mem && $mem->is_admin;
			}
			return $r->error("Permission Denied","Sorry, you don't have permission to edit this group") if !$can_edit;
			
			my $tmpl = $self->get_template('groups/edit.tmpl');
			
			$tmpl->param($_ => $group->get($_)) foreach $group->columns;
			
			my @members = PHC::Group::Member->search(groupid => $group->id);
			foreach my $mbr (@members)
			{
				$mbr->{$_} = $mbr->get($_) foreach $mbr->columns;
				$mbr->{member_name} = $mbr->userid->display if $mbr->userid;
			}
			$tmpl->param(members => \@members);
			
			# Not worrying about admin because user must be an "amin of this group" to edit
			#my $admin = $user && $user->check_acl($MGR_ACL) ? 1:0;
			#$tmpl->param(is_admin => $admin);
			
			$tmpl->param(manager_list => AppCore::User->tmpl_select_list($group->managerid,1));
			$tmpl->param(new_members => AppCore::User->tmpl_select_list(0,1));
			#$tmpl->param(spouse_users => AppCore::User->tmpl_select_list($group->spouse_userid,1));
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Edit Group',$self->module_url('/edit?groupid='.$fam),0);
			$view->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'new')
		{
			AppCore::AuthUtil->require_auth(['ADMIN','Pastor']);
			
			my $tmpl = $self->get_template('groups/edit.tmpl');
			
			my $admin = $user && $user->check_acl([qw/ADMIN Pastor/]) ? 1:0;
			$tmpl->param(is_admin => $admin);
			
			$tmpl->param(users => AppCore::User->tmpl_select_list(undef,1));
			$tmpl->param(spouse_users => AppCore::User->tmpl_select_list(undef,1));
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('New Family',$self->module_url('/new'),0);
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
			
			# Anyone can edit these columns (anyone, well, anyone who has permission)
			my @cols = qw/
				folder_name
				title
				tagline
				description
				contact_person
				contact_personid
				phone
				email
			/;
			
			# Add in admin-only columns
			if($admin)
			{
				push @cols, qw/managerid member_approval_required access_members_only listed_publicly/;
			}
			
			# Update data fields
			foreach my $col (@cols)
			{
				#print STDERR "Checking col: $col ($req->{$col})\n";
				$group->set($col, $req->{$col}) if defined $req->{$col};
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
				PHC::Group::Member->insert({
					groupid		=> $group->id,
					userid		=> $req->{new_member_userid},
					role		=> $req->{role_new},
					is_admin	=> $req->{admin_new} ? 1:0,
				});
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
				foreach (qw/managerid folder_name title/)
				{
					$group->boardid->set($_, $group->get($_))
						     if $group->boardid->get($_) ne
							         $group->get($_);
				}
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
				return $r->redirect($self->binpath.'#'.$group->id);
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
			
			my $length = 10;
			
			if($req->{search} && $req->output_fmt ne 'json')
			{
				# Require at least 3 letters if not using json
				return $r->error("At least 3 letters","You need at least 3 letters to search") if length $req->{search} < 3;
			}
			
			#@directory = @directory[$start .. $start+$count];
			my $directory_data = $self->load_groups_list($req->{search} ? $req->{search} : ($start, $length));
			
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
		
		my $user = AppCore::Common->context->user;
		my $sub_page = $req->next_path;
		
		if($sub_page eq 'new' || $sub_page eq 'post' || $sub_page eq 'edit')
		{
			# Board actions - TODO test and see if more actiosn need to be routed
			$self->SUPER::board_page($req,$r,$group->boardid);
		}
		elsif($sub_page eq 'new_event' || $sub_page eq 'post_event' || $sub_page eq 'edit_event')
		{
			# TODO wrap these actions and make event handlers for these actions
		}
		else
		{
			my $tmpl = $self->get_template('groups/group_page.tmpl');
			
			$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			
			# Load posts
			my $data = $self->load_post_list($group->boardid);
			$tmpl->param('posts_'.$_ => $data->{$_}) foreach keys %$data;
			
			# Note forced stringification required below.
			$tmpl->param('posts_approx_time' => ''.approx_time_ago($data->{first_ts}));
			
			# Load events
			my $events_data = ThemePHC::Events->load_basic_events_data($group);
		
			#die Dumper $out_weekly, \@dated;
			$tmpl->param(events_weekly => $events_data->{weekly});
			$tmpl->param(events_dated  => $events_data->{dated});
		
			my $view = Content::Page::Controller->get_view('sub',$r);
			#$view->breadcrumb_list->push('Groups Home',$self->module_url(),0);
			$view->breadcrumb_list->push($group->title,$self->module_url('/'.$group->folder_name),0);
			$view->output($tmpl);
			return $r;
		}
	}
}


1;