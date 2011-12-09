// Script: calendar.js
// Basic calendar popup
//
	var buttonNum=0;
	function makeCalButton(retName)
	{
		var bn = 'cal'+(buttonNum++);
		var icon = window.calendarIcon ? window.calendarIcon : "/appcore/images/silk/calendar.png";
		var html = '<a href="javascript:toggleDatePicker(\''+bn+'\',\''+retName+'\')"><img id='+bn+'Pos name='+bn+'Pos src="'+icon+'" align=absmiddle border=0 alt="Date Picker"></a><div id="'+bn+'" style="position:absolute;"></div>';
		//alert(html);'
		
		document.write(html);
	}
	
	// fixPosition() attaches the element named eltname
	// to an image named eltname+'Pos'
	//
	function fixPosition(divname) 
	{
		divstyle = getDivStyle(divname);
		positionerImgName = divname + 'Pos';
		// hint: try setting isPlacedUnder to false
		isPlacedUnder = false;
		if (isPlacedUnder) 
		{
			setPosition(divstyle,positionerImgName,true);
		} 
		else 
		{
			setPosition(divstyle,positionerImgName)
		}
	}
	
	function toggleDatePicker(eltName,formElt) 
	{
		
		try 
		{ 
			// some sort of external integration ??
			if(g_blur_tid!=-1) 
				clearTimeout(g_blur_tid);
		} 
		catch(e) {}
		
		var x = formElt.indexOf('.');
		///debug("toggleDatePicker for '"+formElt+"'");
		
		var usedFormMode = true;
		if(x>-1)
		{
			var formName    = formElt.substring(0,x);
			var formEltName = formElt.substring(x+1);
			var form        = document.forms[formName];
			if(!form)
				form = document.getElementById(formName);
				
			if(!form)
			{
				var elm = document.getElementById(formEltName);
				if(!elm)
					elm = document.getElementById(formElt);
				newCalendar(eltName,elm,0);
			}
			else
			{
				if(form.elements)
				{
					newCalendar(eltName,form.elements[formEltName],0);
				}
				else
				{
					usedFormMode = false;
				}
			}
		}
		
		if(x<0 || !usedFormMode)
		{
			var eltId = formElt; //formElt.substring(1,formElt.length);
			var elt = document.getElementById(eltId);
			//alert(eltId+','+elt);
			newCalendar(eltName,elt,0);
		}
		//alert(1);
		toggleVisible2(eltName);
	}
	
	// fixPositions() puts everything back in the right place after a resize.
	function fixPositions()
	{
		// add a fixPosition call here for every element
		// you think might get stranded in a resize/reflow.
		//fixPosition('daysOfMonth');
		//fixPosition('josiah1');
	}
	
		
	// how reliable is this test?
        isIE = (document.all ? true : false);
	isDOM = (document.getElementById ? true : false);

        // Initialize arrays.
	var months = new Array("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
	var daysInMonth = new Array(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
	var displayMonth = new Date().getMonth();
	var displayYear = new Date().getFullYear();
	var displayDay = '-1';
	var displayDivName;
	var displayElement;

        function getDays(month, year) 
        {
		// Test for leap year when February is selected.
		if (1 == month)
			return ((0 == year % 4) && (0 != (year % 100))) ||
				(0 == year % 400) ? 29 : 28;
		else
			return daysInMonth[month];
        }
	
	function getToday() 
	{
		// Generate today's date.
		this.now   = new Date();
		this.year  = this.now.getFullYear();
		this.month = this.now.getMonth();
		this.day   = this.now.getDate();
	}
	
	// Start with a calendar for today.
	today = new getToday();
	//var displayElementLookup = {};


        function newCalendar(eltName,attachedElement,ignore) 
        {
		if (attachedElement) 
		{
			if (displayDivName && displayDivName != eltName) hideElement(displayDivName);
			displayElement = attachedElement;
		}
		displayDivName = eltName;
		today = new getToday();
		
		
		//displayElementLookup[eltName] = displayElement;
		
		newCalendar.originalTime = null;
		
		// auto code here
		
		if(displayElement && displayElement.value != '' && !ignore)
		{
			var val = displayElement.value;
			if(val.match(/\s/))
			{
				var dt = val.split(/\s/);
				newCalendar.originalTime = dt[1];
				val = dt[0];
			}
			var m = val.split("-");
			var newDate = new Date(m[0],m[1]-1,m[2]);
			//console.debug("m="+m+",nd="+newDate+",m[0]='"+m[0]+"'");
			if(""+newDate != "Invalid Date" && m[0]!="0000")
			{
				
				displayMonth = newDate.getMonth();
				displayYear  = newDate.getFullYear();
				today.year = displayYear;
				today.month = displayMonth;
				today.day = newDate.getDate();
				displayDay = -1;
				//console.debug("Tripped");
			}
			
		}
		
		var parseYear  = parseInt(displayYear  + '');
		var parseMonth = parseInt(displayMonth + '');
		var day        = parseInt(displayDay + '');
		
		var newCal      = new Date(parseYear,parseMonth,day>0?day:1);
		var startDayOfWeek = newCal.getDay();
		
		if ((today.year  == newCal.getFullYear()) &&
		    (today.month == newCal.getMonth()  ) && day==-1)
		{
			day = today.day;
		}
		
		var intDaysInMonth = getDays(newCal.getMonth(), newCal.getFullYear());
		var daysGrid       = makeDaysGrid(startDayOfWeek,day,intDaysInMonth,newCal,eltName)
		
		if (isIE) 
		{
			var elt = document.all[eltName];
			elt.innerHTML = daysGrid;
		} 
		else if (isDOM) 
		{
			var elt = document.getElementById(eltName);
			elt.innerHTML = daysGrid;
		} 
		else 
		{
			var elt = document.layers[eltName].document;
			elt.open();
			elt.write(daysGrid);
			elt.close();
		}
	}

	function incMonth(delta,eltName) 
	{
		displayMonth += delta;
		if (displayMonth >= 12) {
			displayMonth = 0;
			incYear(1,eltName);
		} else if (displayMonth <= -1) {
			displayMonth = 11;
			incYear(-1,eltName);
		} else {
			newCalendar(eltName,0,1);
		}
	}

	function incYear(delta,eltName) 
	{
		displayYear = parseInt(displayYear + '') + delta;
		newCalendar(eltName,0,1);
	}

	function makeDaysGrid(startDay,day,intDaysInMonth,newCal,eltName) 
	{
		var daysGrid;
		var month = newCal.getMonth();
		var year  = newCal.getFullYear();
		var isThisYear  = (year == new Date().getFullYear());
		var isThisMonth = (day > -1);
		
		daysGrid = '<table border=0 style="border: 1px solid black;background: rgb(220,220,220);font-family: Arial;font-size: 12px;" cellspacing=0 cellpadding=0><tr><td nowrap>';
		//daysGrid += '<font face="courier new, courier" size=2>';
		daysGrid += '<table style="margin: 2pt;" border=0 cellspacing=0 cellpadding=0 width=100%><tr><td>';
		daysGrid += '<a style="color: rgb(0,0,0);font-weight: bold;" href="javascript:hideElement(\'' + eltName + '\')">&nbsp;x&nbsp;</a>';
		//daysGrid += '&nbsp;&nbsp;';
		daysGrid += '</td><td align=center>';
		
		daysGrid += '<a style="color: rgb(0,0,0);" href="javascript:incMonth(-1,\'' + eltName + '\')">&laquo; </a>';
		daysGrid += '<b>';
		if (isThisMonth)
			daysGrid += '<span id=thismonth>' + months[month] + '</span>';
		else
			daysGrid += '<span id=month>'     + months[month] + '</span>';
		daysGrid += '</b>';
		daysGrid += '<a style="color: rgb(0,0,0);" href="javascript:incMonth(1,\'' + eltName + '\')"> &raquo;</a>';
		
		
		daysGrid += '&nbsp;&nbsp;&nbsp;';
		
		
		daysGrid += '<a style="color: rgb(0,0,0);" href="javascript:incYear(-1,\'' + eltName + '\')">&laquo; </a>';
		daysGrid += '<b>';
		if (isThisYear)
			daysGrid += '<span id=thisyear>' + year + '</span>';
		else
			daysGrid += '<span id=year>' + year + '</span>';
		daysGrid += '</b>';
		daysGrid += '<a style="color: rgb(0,0,0);" href="javascript:incYear(1,\'' + eltName + '\')"> &raquo;</a><br>';
		
		
		daysGrid += '</td><td>&nbsp;&nbsp;&nbsp;';
		daysGrid += '</td></tr></table>';
		
		daysGrid += '<table border=0 style="background: rgb(255,255,255);" cellspacing=0 cellpadding=0>';
		//daysGrid += '&nbsp;Su Mo Tu We Th Fr Sa&nbsp;<br>&nbsp;';
		daysGrid += '<tr><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Su</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Mo</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Tu</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">We</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Th</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Fr</th><th style="background: rgb(0,0,0);color: rgb(255,255,255);font-weight: bold;font-size: 10px;">Sa</th></tr>';
		
		var dayOfMonthOfFirstSunday = (7 - startDay + 1);
		for (var intWeek = 0; intWeek < 6; intWeek++) 
		{
			daysGrid += '<tr>'
			var dayOfMonth;
			for (var intDay = 0; intDay < 7; intDay++)
			{
				dayOfMonth = (intWeek * 7) + intDay + dayOfMonthOfFirstSunday - 7;
				if (dayOfMonth <= 0) 
				{
					daysGrid += "<td>&nbsp;</td> ";
				} 
				else if (dayOfMonth <= intDaysInMonth) 
				{
					daysGrid += '<td style="border: 1px solid rgb(230,230,230);">';
					var id="color: rgb(0,0,0);font-weight: bold;padding: 2px 5px;";
					
					if (day > 0 && day == dayOfMonth) 
						id = "color: rgb(0,255,0);font-weight: bold;padding: 2px 5px;";
						
					daysGrid += '<a style="'+id+'" href="javascript:setDay(';
					daysGrid += dayOfMonth + ',\'' + eltName + '\')"> '
					
					var dayString = dayOfMonth + "</a> ";
					if (dayString.length == 6) 
						dayString = '0' + dayString;
						
					daysGrid += dayString;
					daysGrid += '</td>';
				}
			}
			if (dayOfMonth < intDaysInMonth) 
				daysGrid += "</tr>";
			//daysGrid += '</tr>';
		}
		daysGrid += '</table>';
		return daysGrid + "</td></tr></table>";
	}

	function setDay(day,eltName) 
	{
		//displayElement.value = (displayMonth + 1) + "/" + day + "/" + displayYear;
		//displayElement = displayElementLookup[eltName];
		if(displayElement && !displayElement.xFieldReadonly)
		{
			if(!newCalendar.originalTime && displayElement.className && displayElement.className.match(/x-type-datetime/))
				newCalendar.originalTime = "00:00:00";
			displayElement.value = displayYear + '-' + rpad(displayMonth + 1) + "-" + rpad(day) + (newCalendar.originalTime ? " "+newCalendar.originalTime : "");
			if(typeof(displayElement.onchange) == "function")
				displayElement.onchange();
		}
		hideElement(eltName);
	}
	 
	function rpad(v) { v=''+v; if(v.length<2) return '0'+v; return v; }

	 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// the rest of this was originally in a file called tjmlib.js	 

// overly simplistic test for IE
isIE = (document.all ? true : false);
// both IE5 and NS6 are DOM-compliant
isDOM = (document.getElementById ? true : false);

// get the true offset of anything on NS4, IE4/5 & NS6, even if it's in a table!
function getAbsX(elt) { return (elt.x) ? elt.x : getAbsPos(elt,"Left"); }
function getAbsY(elt) { return (elt.y) ? elt.y : getAbsPos(elt,"Top"); }
function getAbsPos(elt,which) {
 iPos = 0;
 while (elt != null) {
  iPos += elt["offset" + which];
  elt = elt.offsetParent;
 }
 return iPos;
}

function getDivStyle(divname) {
 var style;
 if (isDOM) {
 //debug(divname); 
 var x= document.getElementById(divname);
 if(!x) return null;
 style = x.style; }
 else { style = isIE ? document.all[divname].style
                     : document.layers[divname]; } // NS4
 return style;
}

function hideElement(divname) {
 var x = getDivStyle(divname);
 if(!x) return null;
 x.display = 'none';
}

// annoying detail: IE and NS6 store elt.top and elt.left as strings.
function moveBy(elt,deltaX,deltaY) {
 elt.left = parseInt(elt.left) + deltaX;
 elt.top = parseInt(elt.top) + deltaY;
}

function toggleVisible2(divname) {
	
 divstyle = getDivStyle(divname);
 if (divstyle.display == 'block' || divstyle.display == 'show') {
   divstyle.display = 'none';
 } else {
 	
   //fixPosition(divname);
   divstyle.display = 'block';
 }
}

function setPosition(elt,positionername,isPlacedUnder) {
 var positioner;
 if (isIE) {
  positioner = document.all[positionername];
 } else {
  if (isDOM) {
    positioner = document.getElementById(positionername);
  } else {
    // not IE, not DOM (probably NS4)
    // if the positioner is inside a netscape4 layer this will *not* find it.
    // I should write a finder function which will recurse through all layers
    // until it finds the named image...
    positioner = document.images[positionername];
  }
 }
 elt.left = getAbsX(positioner);
 if(elt.left + elt.clientWidth > document.body.clientWidth)
 	elt.left = document.body.clientWidth - elt.clientWidth;
 elt.top = getAbsY(positioner) + (isPlacedUnder ? positioner.height : 0);
}
