use strict;

package PHC::Recipe;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> 'recipe',
		
		schema	=> 
		[
			{ field => 'recipeid',		type => 'int', @AppCore::DBI::PriKeyAttrs},
			{ field	=> 'enteredby',		type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'timestamp',		type => 'timestamp' },
			{ field	=> 'title',		type => 'varchar(255)' },
			{ field	=> 'author',		type => 'varchar(255)' },
			{ field	=> 'instructions',	type => 'text'	},
			{ field	=> 'servings',		type => 'float',	},
			{ field	=> 'cook_type',		type => "enum('Stove','Oven','Crockpot','Toaster','Toaster Oven','No Cook')", default=>'Stove'	},
			{ field	=> 'speed',		type => "enum('Quick','Medium','Long')", 		default=>'Quick'	},
			#{ field	=> 'primary_category',	type => "enum('Main Dish','Side Dish','Dessert')", title => 'Main Category' },
			{ field	=> 'category',		type => 'varchar(255)' },
		],	
	});
	
#	__PACKAGE__->has_many(lines => 'PHC::Recipe::Line');
	sub lines 
	{
		my $self = shift;
		return PHC::Recipe::Line->search( recipeid => $self->id );
	}
	
	sub distinct_categories
	{
		my $pkg = shift;
		my $cur = shift;
		my $sel_flag = shift || 0;
		
		my $distinct_sth = $pkg->db_Main->prepare_cached('select distinct category from '.$pkg->table.' where category<>"" and category is not null');
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
	
}


package PHC::Recipe::FoodItem;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> 'recipe_fooditem',
		
		schema	=> 
		[
			{ field => 'itemid',			type => 'int', @AppCore::DBI::PriKeyAttrs},
			{ field	=> 'name',			type => 'varchar(255)' },
		],	
	});
	
	__PACKAGE__->set_sql(name_soundslike => 'select * from recipe_fooditem where name sounds like ?');
}


package PHC::Recipe::Line;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> 'recipe_line',
		
		schema	=> 
		[
			{ field => 'lineid',		type => 'int', @AppCore::DBI::PriKeyAttrs},
			{ field => 'recipeid',		type => 'int',	linked => 'PHC::Recipe' },
			{ field	=> 'itemid',		type => 'int',	linked => 'PHC::Recipe::FoodItem' },
			{ field	=> 'fraction_qty',	type => 'varchar(20)' },
			{ field	=> 'quantity',		type => 'float' },
			{ field	=> 'um',		type => 'varchar(20)' },
		],	
	});
}


package ThemePHC::Recipes;
{
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	use Content::Page;
	
	use Boards::Data;
	
 	use JSON qw/decode_json encode_json/;
# 	use LWP::Simple qw/get/;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Recipe Database','PHC Recipe Database',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	use DateTime;
	use AppCore::Common;
	#use JSON qw/to_json/;
	
	my $CREATE_ACL = [qw/malorie.dunlap@indwes.edu ADMIN/];
	
	# to move bulk upload files
	use File::Copy;

	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::Recipe
			PHC::Recipe::Line
			PHC::Recipe::FoodItem
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		return $self;
	};
	
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
		
		return $self->recipe_page($req,$r);
	};
	
	sub item_for_name
	{
		my $self = shift;
		my $name = shift;
		my $item = PHC::Recipe::FoodItem->by_field(name => $name);
		
		if(!$item)
		{
			my @results = PHC::Recipe::FoodItem->search_name_soundslike($name);
			$item = shift @results if @results;
		}
		
		if(!$item)
		{
			$item = PHC::Recipe::FoodItem->insert({name=>$name});
		}
		return $item;
	}
	
	
	sub recipe_page
	{
		my ($self,$req,$r) = @_;
		
		my $sub_page = $req->next_path;
		
		my $user = AppCore::Common->context->user;
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		if($sub_page eq 'new')
		{
			AppCore::AuthUtil->require_auth($CREATE_ACL);
			
			# Load the editing template
			my $tmpl = $self->get_template('recipes/edit.tmpl');
			
			$tmpl->param(categories => PHC::Recipe->distinct_categories(undef,1)); # 1 = return in a 'tmpl_select_list' format
			
			# Output the template
			$view->breadcrumb_list->push('Create New Recipe',$self->module_url($sub_page),0);
			return $view->output($tmpl);
		}
		elsif($sub_page eq 'edit')
		{
			AppCore::AuthUtil->require_auth($CREATE_ACL);
			
			# Load the recipe
			my $recipe = PHC::Recipe->retrieve($req->recipeid);
			return $r->error('No Such Recipe','Sorry, the recipe ID you gave does not exist.') if !$recipe;
			
			# Apply the recipe to the template
			my $tmpl = $self->get_template('recipes/edit.tmpl');
			$tmpl->param($_ => $recipe->get($_)) foreach $recipe->columns;
			
			# Load and apply the lines to the template
			my @lines = $recipe->lines;
			@lines = sort {$a->lineid <=> $b->lineid} @lines;
			
			my $delete_base = $self->binpath . '/delete_line?recipeid='.$recipe->id.'&lineid=';
			
			# Mudge @lines for use in the template
			foreach my $line (@lines)
			{
				$line->{$_} = $line->get($_) foreach $line->columns;
				$line->{item_name} = $line->itemid && $line->itemid->id ? $line->itemid->name : "";
				$line->{delete_url} = $delete_base . $line->id;
			}
			$tmpl->param(lines => \@lines);
			$tmpl->param(delete_url => $self->binpath . '/delete?recipeid='.$recipe->id);
			$tmpl->param(categories => PHC::Recipe->distinct_categories($recipe->category,1)); # 1 = return in a 'tmpl_select_list' format
			
			# Output the template
			$view->breadcrumb_list->push('Edit '.$recipe->title,$self->module_url($sub_page),0);
			return $view->output($tmpl);
		}
		elsif($sub_page eq 'post')
		{
			AppCore::AuthUtil->require_auth($CREATE_ACL);
			
			my $recipe;
			
			# Create if needed, otherwise retrieve from DB
			my $id = $req->recipeid;
			if(!$id)
			{
				$recipe = PHC::Recipe->insert({ enteredby => $user });
			}
			else
			{
				$recipe = PHC::Recipe->retrieve($id);
			}
			
			if($req->category eq '_')
			{
				$req->{category} = $req->{category_new};
			}
			
			
			my @keys = qw/
				title
				author
				instructions
				servings
				cook_type
				speed
				category
			/;
			foreach my $col (@keys)
			{
				$recipe->set($col, $req->$col) if defined $req->$col;
			}
			$recipe->update;
			
			my @lines = $recipe->lines;
			foreach my $line (@lines)
			{
				my $id = $line->id;
				$line->um($req->{'line_'.$id.'_um'});
				$line->fraction_qty($req->{'line_'.$id.'_fraction_qty'});
				$line->quantity($req->{'line_'.$id.'_quantity'});
				$line->itemid($self->item_for_name($req->{'line_'.$id.'_name'}));
				$line->update;
			}
			
			if($req->{line_new_name})
			{
				PHC::Recipe::Line->insert({
					recipeid => $recipe, 
					um => $req->{'line_new_um'},
					fraction_qty => $req->{'line_new_fraction_qty'},
					quantity => $req->{'line_new_quantity'},
					itemid => $self->item_for_name($req->{'line_new_name'}),
				});
			}
			
			if($req->{add_another})
			{
				return $r->redirect($self->binpath.'/edit?recipeid='.$recipe->id.'#add_another');
			}
			
			return $r->redirect($self->binpath.'#'.$recipe->title);
		}
		elsif($sub_page eq 'delete')
		{
			AppCore::AuthUtil->require_auth($CREATE_ACL);
			
			# Load the recipe
			my $recipe = PHC::Recipe->retrieve($req->recipeid);
			return $r->error('No Such Recipe','Sorry, the recipe ID you gave does not exist.') if !$recipe;
			
			# Delete the object
			$recipe->delete;
			
			return $r->redirect($self->module_url);
		}
		elsif($sub_page eq 'delete_line')
		{
			AppCore::AuthUtil->require_auth($CREATE_ACL);
			
			# Load the recipe
			my $recipe = PHC::Recipe->retrieve($req->recipeid);
			return $r->error('No Such Recipe','Sorry, the recipe ID you gave does not exist.') if !$recipe;
			
			# Locate the line
			my $line = PHC::Recipe::Line->retrieve($req->lineid);
			return $r->error('No Such Line','Sorry, the recipe line you gave does not exist.') if !$line;
			
			# Delete the line
			$line->delete;
			
			return $r->redirect($self->binpath.'/edit?recipeid='.$recipe->id);
		}
		elsif($sub_page eq 'pdf')
		{
			# TODO Regenerate PDF if out of date ...
			
			# Just send file
			return $r->output_file(AppCore::Config->get('WWW_DOC_ROOT') . AppCore::Config->get('WWW_ROOT') . '/mods/ThemePHC/downloads/PHCRecipeBook.pdf','application/pdf');
		}
		
		elsif($sub_page)
		{
			# Locate the recipe
			my $recipe = PHC::Recipe->retrieve($sub_page);
			return $r->error('No Such Recipe','Sorry, the recipe ID you gave does not exist.') if !$recipe;
			
			# Apply recipe to template
			my $tmpl = $self->get_template('recipes/view.tmpl');
			$tmpl->param($_ => $recipe->get($_)) foreach $recipe->columns;
			
			my $instr = AppCore::Web::Common->text2html($recipe->instructions);
			$tmpl->param(instructions_html => $instr);
			
			# Load and apply the lines to the template
			my @lines = $recipe->lines;
			@lines = sort {$a->lineid <=> $b->lineid} @lines;
			
			# Mudge @lines for use in the template
			foreach my $line (@lines)
			{
				$line->{$_} = $line->get($_) foreach $line->columns;
				$line->{item_name} = $line->itemid && $line->itemid->id ? $line->itemid->name : "";
				$line->{is_header} = $line->um eq '-';
				#die Dumper $line if $line->{item_name} eq 'toast';
			}
			$tmpl->param(lines => \@lines);
			
			if(($_ = AppCore::Common->context->user) && $_->check_acl($CREATE_ACL))
			{
				$tmpl->param(can_edit => 1);
				$tmpl->param(edit_url => $self->binpath.'/edit?recipeid='.$recipe->id);
				$tmpl->param(delete_url => $self->binpath.'/delete?recipeid='.$recipe->id);
			} 
			
			# Output the template
			$view->breadcrumb_list->push($recipe->title,$self->module_url($sub_page),0);
			return $view->output($tmpl);
		}
		else
		{
			my $tmpl = $self->get_template('recipes/main.tmpl');
			
			$tmpl->param(can_create =>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($CREATE_ACL);
			
			my $bin = $self->binpath;
			
			my $start = $req->{start} || 0;
			
			$start =~ s/[^\d]//g;
			$start = 0 if !$start || $start<0;
			
			
			my $count_sth = PHC::Recipe->db_Main->prepare('select count(recipeid) as `count` from recipe');
			$count_sth->execute;
			
			my $count = $count_sth->rows ? $count_sth->fetchrow_hashref->{count} : 0;
			
			my $length = 100;
			$start = $count - $length if $start + $length > $count;
			$start = 0 if $start < 0;
			
			$tmpl->param(count => $count);
			$tmpl->param(pages => int($count / $length)+1);
			$tmpl->param(cur_page => int($start / $length) + 1);
			$tmpl->param(next_start => $start + $length);
			$tmpl->param(prev_start => $start - $length);
			$tmpl->param(is_end => $start + $length == $count);
			$tmpl->param(is_start => $start <= 0);
			
			my @recipes = PHC::Recipe->retrieve_from_sql(qq{
				1 
				
				order by title desc
				
				limit $start, $length
			});#search(published=>1);
			#@recipes = sort { $b->title cmp $a->title } @recipes;
			foreach my $s (@recipes)
			{
				$s->{$_} = $s->get($_) foreach $s->columns;
				$s->{bin} = $bin;
			}
			$tmpl->param(recipes => \@recipes);
			
			return $view->output($tmpl);
		}
	}
	
}

1;
