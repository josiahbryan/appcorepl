(function($) {

/*
* Auto-growing textareas; technique ripped from Facebook
*/
	function times(string, number) 
	{
		for (var i = 0, r = ''; i < number; i ++) r += string;
		return r;
	};
		
	$.fn.autogrow = function(options) {
		
		this.filter('textarea').each(function() {
		
			var 	$this = $(this),
				minHeight = $this.height(),
				lineHeight = parseInt($this.css('lineHeight')),
				
				shadow = $('<div></div>').css({
					position: 'absolute',
					top: -10000,
					left: -10000,
					width: $(this).width() - parseInt($this.css('paddingLeft')) - parseInt($this.css('paddingRight')),
					fontSize: $this.css('fontSize'),
					fontFamily: $this.css('fontFamily'),
					lineHeight: $this.css('lineHeight'),
					resize: 'none',
					textIndent: 0,
				}).appendTo(document.body),
				
				update = function() {
			
					var val = this.value.replace(/</g, '&lt;')
							.replace(/>/g, '&gt;')
							.replace(/&/g, '&amp;')
							.replace(/\n$/, '<br/>&nbsp;')
							.replace(/\n/g, '<br/>')
							.replace(/ {2,}/g, function(space) { return times('&nbsp;', space.length -1) + ' ' });
					
					shadow.html(val); // + "<br><br>");
					//alert(lineHeight);
					$(this).css('height', Math.max(shadow.height() + lineHeight, minHeight));
			
				};
		
			$(this).change(update).keyup(update).keydown(update);
			this.updateAutogrow = update;
			
			update.apply(this);
		
		});
		
		return this;
		
	}
    
})(jQuery);

// (function($) {
// 	
// 	/*
// 	* Auto-growing textareas; technique ripped from Facebook
// 	*/
// 	$.fn.autogrow = function(options) 
// 	{
// 		
// 		this.filter('textarea').each(function() 
// 		{
// 		
// 			var     $this       = $(this),
// 				minHeight   = $this.height(),
// 				lineHeight  = $this.css('lineHeight');
// 			
// 			var shadow = $('<div></div>').css({
// 				position:   'absolute',
// 				top:        -10000,
// 				left:       -10000,
// 				width:      $(this).width(),
// 				fontSize:   $this.css('fontSize'),
// 				fontFamily: $this.css('fontFamily'),
// 				lineHeight: $this.css('lineHeight'),
// 				resize:     'none',
// 				textIndent: 0,
// 			}).appendTo(document.body);
// 			
// 			var update = function() 
// 			{
// 				
// 				var val = this.value.replace(/</g, '&lt;')
// 						.replace(/>/g, '&gt;')
// 						.replace(/&/g, '&amp;')
// 						.replace(/\n/g, '<br/>');
// 				
// 				shadow.html(val);
// 				var height = Math.max(shadow.height() + 20, minHeight);
// 				//console.debug(height);
// 				$(this).css('height', height);
// 			}
// 			
// 			//$(this).change(update).keyup(update).keydown(update);
// 			$(this).bind('keyup keydown blur update', update);
// 			
// 			update.apply(this);
// 			
// 		});
// 		
// 		return this;
// 		
// 	}
// 
// 	$.fn.autoGrowInput = function(o) 
// 	{
// 	
// 		o = $.extend({
// 			maxWidth: 1000,
// 			minWidth: 0,
// 			comfortZone: 70
// 		}, o);
// 	
// 		this.filter('input:text').each(function()
// 		{
// 		
// 			var minWidth = o.minWidth || $(this).width(),
// 				val = '',
// 				input = $(this),
// 				testSubject = $('<div/>').css({
// 					position: 'absolute',
// 					top: -9999,
// 					left: -9999,
// 					width: 'auto',
// 					fontSize: input.css('fontSize'),
// 					fontFamily: input.css('fontFamily'),
// 					fontWeight: input.css('fontWeight'),
// 					letterSpacing: input.css('letterSpacing'),
// 					whiteSpace: 'nowrap',
// 					textIndent: 0,
// 				}),
// 				check = function() 
// 				{
// 					if (val === (val = input.val())) {return;}
// 			
// 					// Enter new content into testSubject
// 					var escaped = val.replace(/&/g, '&amp;').replace(/\s/g,'&nbsp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// 					testSubject.html(escaped);
// 			
// 					// Calculate new width + whether to change
// 					var testerWidth  = testSubject.width(),
// 						newWidth = (testerWidth + o.comfortZone) >= minWidth ? testerWidth + o.comfortZone : minWidth,
// 						currentWidth = input.width(),
// 						isValidWidthChange = (newWidth < currentWidth && newWidth >= minWidth)
// 								  || (newWidth > minWidth && newWidth < o.maxWidth);
// 			
// 					// Animate width
// 					if (isValidWidthChange) 
// 					{
// 						input.width(newWidth);
// 					}
// 				};
// 		
// 			testSubject.insertAfter(input);
// 		
// 			$(this).bind('keyup keydown blur update', check);
// 			
// 			$(this).check();
// 		
// 		});
// 	
// 		return this;
// 	};
// 
// })(jQuery);