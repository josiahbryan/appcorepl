use strict;
package Content::Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';

	my $PAGE_CREATE_ACTION = 'create';
	my $PAGE_EDIT_ACTION   = 'edit';
	my $PAGE_DELETE_ACTION = 'delete';
	my $PAGE_SAVE_ACTION   = 'save';
	
	__PACKAGE__->WebMethods(qw/ 
		main
		create
		edit
		delete
		save
		set_in_menus
		change_idx
		save_title
	/);


	sub new { bless {}, shift }
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#my $view = Content::Page::Controller->get_view('admin',$r);
		
		#die Dumper $req;
		Content::Page::Controller->current_view->breadcrumb_list->last_crumb->{current} = 1;
			
		
		my $tmpl = $self->get_template('list.tmpl');
		my $binpath = $self->binpath;
		my $modpath = $self->modpath;
		
		my @pages = Content::Page->retrieve_from_sql('1 order by menu_index, url');
		
		use Data::Dumper;
		
		my @cols = Content::Page->columns;
		my @list;
		my $idx_cnt = 0;
		my $tab_cnt = 0;
		foreach my $page (@pages)
		{
			my $row = {};
			$row->{$_} = $page->get($_) foreach @cols;
			$row->{binpath} = $binpath;
			$row->{modpath} = $modpath;
			$row->{tab_idx} = $tab_cnt++;
			
			my @url = split /\//, $row->{url};
			shift @url;
			push @url, "<b>". pop(@url). "</b>";
			if(@url == 1)
			{
				$url[0] = "<span class='toplevel'>" . $url[0] . "</span>";
			}
			
			$row->{url_pretty} = '<span class=util>/</span>' . join('<span class=util>/</span>', @url); 
			$row->{in_menus} = $row->{show_in_menus} ? '<b>Yes</b>' : 'No';
			
			if(!$page->menu_index)
			{
				$row->{menu_index} = $idx_cnt ++;
				$page->menu_index($row->{menu_index});
				$page->update;
			}
			
			my @idx_parts = split /\./, $page->menu_index;
			my $cur = pop @idx_parts;
			my $pre = join '.', map{ $_+0 } @idx_parts;
			$row->{menu_index_pre} = $pre;
			$row->{menu_index_cur} = $cur+0;
			
			#die Dumper $row;
			push @list, $row;
		}
		
		$tmpl->param(pages => \@list);
		$tmpl->param(st => $req->st);
		#die Dumper \@pages;
		
		#$view->output($tmpl);
		$r->output($tmpl);
		return $r;
		
		
	};
	
	sub create
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		Content::Page::Controller->current_view->breadcrumb_list->push("Create New Page",$self->binpath.'/create',1);
		
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		
		$tmpl->param(page_title => AppCore::Common::guess_title($url));
		$tmpl->param(page_content => '');
		$tmpl->param(server_name => $AppCore::Config::WEBSITE_SERVER);
		
		$tmpl->param(themes => Content::Page::ThemeEngine->tmpl_select_list);
		
		my $cur_theme = Content::Page::ThemeEngine->by_field(controller => Content::Page::Controller->theme());
		$tmpl->param(view_codes => Content::Page::ThemeEngine::View->tmpl_select_list($cur_theme));
		
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
		
	}
	
	sub edit
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		$url = '/' if !$url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->redirect( $self->module_url($PAGE_CREATE_ACTION) . '?url='. $url);
		}
		
		Content::Page::Controller->current_view->breadcrumb_list->push("Edit \"".$page_obj->title."\"",$self->binpath.'/edit?url='.$url,1);
		
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		$tmpl->param(pageid => $page_obj->id);
		
		$tmpl->param(page_title   => $page_obj->title);
		$tmpl->param(page_content => $page_obj->content);
		$tmpl->param(server_name  => $AppCore::Config::WEBSITE_SERVER);
		
		$tmpl->param(themes => Content::Page::ThemeEngine->tmpl_select_list);
		
		my $cur_theme = Content::Page::ThemeEngine->by_field(controller => Content::Page::Controller->theme());
		$tmpl->param(view_codes => Content::Page::ThemeEngine::View->tmpl_select_list($page_obj->view_code ? $page_obj->view_code : 'sub', $cur_theme));
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
	}
	
	sub delete
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		$page_obj->delete;
		
		return $r->redirect($self->module_url());
	}
	
	sub set_in_menus
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		$page_obj->show_in_menus($req->flag);
		$page_obj->update;
		
		if($req->quiet)
		{
			return $r->output_data('text/plain','Thanks for all the fish');
		}
		else
		{
			return $r->redirect($self->module_url().($req->st ? '?st='.$req->st : ''));
		}
	}
	
	sub save_title
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $pageid = $req->pageid;
		
		my $page_obj = Content::Page->retrieve($pageid);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$pageid</b>");
		}
		
		$page_obj->title($req->title);
		$page_obj->update;
		
		if($req->quiet)
		{
			return $r->output_data('text/plain','Thanks for all the fish');
		}
		else
		{
			return $r->redirect($self->module_url());
		}
	}
	
	sub _pad_index
	{
		if(@_ > 1)
		{
			return join '.', map { rpad($_+0,3) } @_;
		}
		
		my $new_num = shift;
		
		my @split = split /\./, $new_num;
		my @list = map { rpad($_+0,3) } @split;
		$new_num = join '.', @list;
		
		return $new_num;
	}
	
	sub _renumber_page
	{
		my $self = shift;
		my $page_obj = shift;
		my $new_num = _pad_index(shift);
		
		my $old_idx = $page_obj->menu_index;
		
		 
		$page_obj->menu_index($new_num);
		$page_obj->update;
		
		my $sth = Content::Page->db_Main->prepare('select pageid from pages where url like ?');
		$sth->execute($page_obj->url.'/%');
		
		while(my $ref = $sth->fetchrow_hashref)
		{
			my $child = Content::Page->retrieve($ref->{pageid});
			
			my $child_idx = $child->menu_index;
			$child_idx =~ s/^$old_idx/$new_num/;
			
			$child->menu_index($child_idx);
			$child->update;
		}
	}
	
	sub change_idx
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		
		my $page_obj;
		 
		my $url = $req->url;
		if($url)
		{
			$page_obj = Content::Page->by_field(url => $url);
			if(!$page_obj)
			{
				return $r->error("No such page","No such page: <b>$url</b>");
			}
		}
		else
		{
			my $id = $req->pageid;
			$page_obj = Content::Page->retrieve($id);
			if(!$page_obj)
			{
				return $r->error("No such page","No such page: <b>$id</b>");
			}
			$url = $page_obj->url;
		}
		
		if($req->idx)
		{
			$self->_change_index($page_obj,$req->idx);
		}
		else
		{
			$self->_move_page($page_obj,$req->dir);
		}
		
		if($req->quiet)
		{
			return $r->output_data('text/plain','Thanks for all the fish');
		}
		else
		{
			return $r->redirect($self->module_url().($req->st ? '?st='.$req->st : ''));
		}
	}
	
	sub _change_index
	{
		my ($self,$page_obj,$idx) = @_;
		
		if($idx =~ /\./)
		{
			my @tmp = split /\./, $idx;
			$idx = shift @tmp;
		}
		
		# Add/subtract one from the current integer
		$idx = 1 if $idx < 1;
		
		my @url_base = split /\//, $page_obj->url;
		pop @url_base;
		my $url_base = join('/', @url_base);
		
		# Find the number of sibling pages to this page 
		my $sth = Content::Page->db_Main->prepare('select count(pageid) as count from pages where url like ?');
		$sth->execute($url_base . '/%');
		
		# Cap the integer for this page at the number of sibling pages
		my $count = $sth->rows ? $sth->fetchrow_hashref->{count} : 0;
		$idx = $count if $idx > $count;
		
		
		my @idx_parts = split /\./, $page_obj->menu_index;
		pop @idx_parts;
		my $idx_base = join '.', @idx_parts;
		
		my $idx_old = $page_obj->menu_index;
		my $idx_new = _pad_index($idx_base ? join '.', $idx_base, $idx : $idx);
		
		my $idx_a = ($idx_new cmp $idx_old) < 0 ? $idx_new : $idx_old;
		my $idx_b = ($idx_new cmp $idx_old) < 0 ? $idx_old : $idx_new;
		
		my $sth = Content::Page->db_Main->prepare('select pageid from pages where menu_index>=? and menu_index<=? order by menu_index');
		$sth->execute($idx_a, $idx_b);
		
		#print STDERR "_change_index: a: $idx_a, b: $idx_b\n";
		
		my @set;
		while(my $id = $sth->fetchrow)
		{
			my $pg = Content::Page->retrieve($id);
			
			#print STDERR "Got WS Pg: ".$pg->url." [".$pg->menu_index." | $idx_old]\n";
			
			next if $pg->menu_index eq $idx_old;
			
			#print STDERR "Got WS Pg: ".$pg->url." [1]\n";
			my $test = $pg->menu_index;
			$test =~ s/^$idx_base\.//g;
			#print STDERR "$test\n";
			next if $test =~ /\./;
			
			#print STDERR "Got WS Pg: ".$pg->url." [GOOD]\n";
			
			
			push @set, $pg;
		}
		
		if($idx_a eq $idx_new) # move @set down to make room for new
		{
			my $counter = $idx + 1;
			foreach my $pg (@set)
			{
				my $tmp = $idx_base ? join '.', $idx_base, $counter ++ : $counter ++;
				#print STDERR "Working Set: ".$pg->url.": [+] $tmp\n";
				$self->_renumber_page($pg, $tmp);
			}
		}
		else
		{
			my $counter = $idx - 1;
			@set = reverse @set;
			foreach my $pg (@set)
			{
				my $tmp = $idx_base ? join '.', $idx_base, $counter -- : $counter --;
				#print STDERR "Working Set: ".$pg->url.": [-] $tmp\n";
				$self->_renumber_page($pg, $tmp);
			}
		}
		
		#print STDERR "Final: ".$page_obj->url.": $idx_new\n";
		$self->_renumber_page($page_obj,$idx_new);
	}
	
	
	sub _move_page
	{
		my ($self,$page_obj,$dir) = @_;
			
		my $url = $page_obj->url;
		
		my $dir = $dir eq 'up' ? -1 : 1;
		
		my @url_parts = split /\//, $page_obj->url;
		
		# Get current idx and split at the dots
		_RECALC_IDX:
		my $idx = $page_obj->menu_index; 
		my @number_parts = split /\./, $idx;
		
		my @url_base = @url_parts;
		pop @url_base;
		my $url_base = join('/', @url_base);
		
		# The number of dotted index parts in the menu_index
		# should match the number of '/' parts in the URL
		if(scalar(@number_parts) != scalar(@url_parts)-1)
		{
			if($url eq '/')
			{
				$page_obj->menu_index(0);
			}
			else
			{
				
				#print STDERR "$url: Corrupt debug: ".Dumper(\@number_parts, \@url_parts)."\n";
				# Index corrupt, rebuild all sibling indexes
				my $sth = Content::Page->db_Main->prepare('select pageid from pages where url like ?');
				$sth->execute($url_base . '/%');
				
				# Must have parent to get the starting index
				my $parent = Content::Page->by_field(url => $url_base);
				if(!$parent)
				{
					die "Menu index for url '$url' corrupt, but could not find parent '$url_base' to use for rebuild";
				}
				my $parent_idx = $parent->menu_index;
				print STDERR "$url: Index corrupt, rebuilding based on parent '".$parent->url.", index: $parent_idx \n";
				
				# Loop thru siblings and just increment the index counter
				my $counter = 0;
				while(my $ref = $sth->fetchrow_hashref)
				{
					my $sib = Content::Page->retrieve($ref->{pageid});
					$sib->menu_index($parent_idx .'.'. $counter ++);
					$sib->update;
					print STDERR "$url: Rebuild: Sib ".$sib->url.", new index: ".$sib->menu_index."\n";
				}
			
				goto _RECALC_IDX;
			}
		}
		
		# Get the current integer for this level of the page (last part of the number)
		my $cur_num = pop @number_parts;
		
		# Add/subtract one from the current integer
		my $new_num = $dir < 0 ? $cur_num - 1 : $cur_num + 1;
		$new_num = 1 if $new_num < 1;
		
		# Find the number of sibling pages to this page 
		my $sth = Content::Page->db_Main->prepare('select count(pageid) as count from pages where url like ?');
		$sth->execute($url_base . '/%');
		
		# Cap the integer for this page at the number of sibling pages
		my $count = $sth->rows ? $sth->fetchrow_hashref->{count} : 0;
		$new_num = $count if $new_num > $count;
		
		# Push the new integer onto the string of integers
		push @number_parts, $new_num;
		
		# Rejoin numbers with dots to form the new menu index
		my $new_idx = _pad_index(@number_parts);
		
		print STDERR "$url: new_idx: '$new_idx'\n";
		if($new_idx ne $idx)
		{
			my $existing_obj = Content::Page->by_field(menu_index => $new_idx);
			
			$self->_renumber_page($page_obj, $new_idx);
			$self->_renumber_page($existing_obj, $idx) if $existing_obj;
		}
	}
	
	sub save
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#use Data::Dumper;
		#print STDERR Dumper $req;
		
		my $pageid  = $req->pageid;
		my $title   = $req->title;
		my $url     = '/' . $req->url;
		my $content = $req->content;
		
		my $page_obj = $pageid ? Content::Page->retrieve($pageid) : undef;
		
		if(!$page_obj)
		{
			my @url_parts = split /\//, $url;
		
			my @url_base = @url_parts;
			pop @url_base;
			my $url_base = join('/', @url_base);
			
			# Must have parent to get the starting index
			my $parent;
			my $parent_idx;
			if($url_base)
			{
				$parent = Content::Page->by_field(url => $url_base);
				if(!$parent)
				{
					die "Must create the parent '$url_base' before creating '$url'";
				}
				$parent_idx = $parent->menu_index;
			}
			
			# Find the number of sibling pages to this page 
			my $sth = Content::Page->db_Main->prepare('select count(pageid) as count from pages where url like ?');
			$sth->execute($url_base . '/%');
		
			# Cap the integer for this page at the number of sibling pages
			my $count = $sth->rows ? $sth->fetchrow_hashref->{count} : 0;
			
			my $idx = ($parent_idx ? ($parent_idx . '.') : '') . ($count+1);
			
			$page_obj = Content::Page->create({
				url	=>	$url, 
				show_in_menus	=> 1,
				menu_index	=> $idx,
			});
			print STDERR "Admin: Created pageid $page_obj for url $url\n";
		}
		
		$page_obj->title($title);
		$page_obj->content($content);
		$page_obj->url($url);
		$page_obj->themeid($req->themeid);
		$page_obj->view_code($req->view_code);
		$page_obj->update;
		
		print STDERR "Admin: Updated pageid $pageid - \"$title\"\n";
		
		my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
		
		return $r->redirect($url_from ? $url_from : $self->module_url());
	}
	
};
1;
