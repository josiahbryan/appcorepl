
DELIMITER //

DROP FUNCTION  IF EXISTS `match_ratio` //
  
CREATE FUNCTION `match_ratio` ( s1 text, s2 text, s3 text ) RETURNS int(11)
	DETERMINISTIC
BEGIN 
	DECLARE s1_len, s2_len, s3_len, max_len INT; 
	DECLARE s3_tmp text;
			
	SET s1_len = LENGTH(s1), 
		s2_len = LENGTH(s2);
	IF s1_len > s2_len THEN  
		SET max_len = s1_len;  
	ELSE  
		SET max_len = s2_len;  
	END IF; 
	
	if max_len = 0 then
		return 0;
	end if;
    
	if lower(s1) like concat('%',lower(s2),'%') then
		return round((1 - (abs(s1_len - s2_len) / max_len)) * 100);
	else
		set s3_tmp = replace(s3, '%', '');
		set s3_len = length(s3_tmp);
		
		
		IF s1_len > s3_len THEN  
			SET max_len = s1_len;  
		ELSE  
			SET max_len = s3_len;  
		END IF; 
		
		if lower(s1) like concat('%',lower(s3),'%') then
			/*round(abs(s1_len - s3len) / max_len * .5 * 100);*/
			return round((1 - (abs(s1_len - s3_len) / max_len)) * .5 * 100);
		else
		
			return 0;
		end if;
	end if;
  
END //
DELIMITER ;
