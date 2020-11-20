###  

##Reads in the passenger_manifest and compares against allowable_countries
#  white_list is the list of allowed countries
#  min_testing_budget is a debugging tool to FORCE that some entries have a minimal available budget after accounting for flags
##Returns 
#  table of testing budget by ports 
#  Augments passenger_manifest with flagging column for black_listed COUNTRIES.  Such passenger may not be tested if no medical personnel at port
adjust_budgets <- function(pass_manifest, port_budgets, white_list = NULL, min_testing_budget = -1e6, log_file = "log.txt"){
  #read in the white_list
  if (is.null(white_list)) {
    white_list <- read_csv("../sample_input_data_fake/countries_allowed.csv", col_names=c("country"))
  }  
  
  pass_manifest <- pass_manifest %>% 
    mutate(cntry_flagged = ! country %in% white_list$country)
  
  tests_for_flag <- pass_manifest %>% filter(cntry_flagged) %>%
    count(point_entry) %>% rename(num_flagged = n)
  
  #Update the budgets on each port 
  #Ports with zero capacity are untouched because despite flagged arrivals, they will not be tested as there are no medical personnel
  port_budgets <- 
    left_join(port_budgets, tests_for_flag, by=c(Entry_point="point_entry")) %>%
    mutate(num_flagged = ifelse(is.na(num_flagged), 0, num_flagged), 
           updated_capacity = ifelse(Capacity > 0, Capacity - num_flagged, 0)) 
  
  rm(tests_for_flag)
  
  #it is possible that some ports use entire budget on flag.  artificially increase them up if debugging
  port_budgets <- mutate(port_budgets, updated_capacity = pmax(min_testing_budget, updated_capacity))
  
  ###Check if certain ports are exceeding budgets due to flags and log.  This should be addressed in PM Meeting
  if( min(port_budgets$updated_capacity) < 0 ){
    cat("\n \n Some ports budgets Exhausted on Black-Listed Countries!\n ", file=log_file, append=TRUE)
    port_budgets %>% filter( updated_capacity < 0 ) %>%
      write_csv(log_file, append=TRUE)
    
    #Round them to zero for purpose of run.
    port_budgets <- mutate(port_budgets, updated_capacity = pmax(0, updated_capacity))
  }
  
  #Clean it up to look right for bandit.
  port_budgets <- port_budgets %>% select(Entry_point, Capacity, updated_capacity, Target_Capacity)
  
  return(list(port_budgets, pass_manifest))
}  

#returns a tibble of params
mm_beta_dist <- function(mom1, mom2){
  ##MM estimates not defined in this case
  if(mom1 <= mom2){ 
    return( tibble(alpha=NA, beta=-1))
  }
  if(mom2 <= mom1^2){
    return( tibble(alpha = -1, beta=NA))
  }
  
  var = mom2 - mom1^2
  alpha = (mom1^2 * (1-mom1)/var - mom1)
  beta = (mom1 *(1-mom1)/var - 1) * (1-mom1)
  return(tibble(alpha=alpha, beta=beta))
}

#Given the moments of each unit, fit alpha-beta parameterss
fit_eb_MM <- function(df, col_mom1, col_mom2, method_name){
  df <- df %>% ungroup() %>%
    mutate(
      "{{method_name}}" := map2({{col_mom1}}, {{col_mom2}}, mm_beta_dist)
    )
  return(df)
}

#Given alpha-beta params and (X, N) data, computes EB estimates
#pred_name is name of new prediction column to be added
#param_name indicates where the tibble of parameters are
#pos_name (resp. total_name) is column of positives (resp. total tested)
add_eb_preds <- function(df, pred_name, param_name, pos_name, total_name){
  df %>% ungroup() %>% unnest(cols= {{param_name}}) %>%
    mutate(
      alpha.post = alpha + {{pos_name}}, 
      beta.post  = beta + {{total_name}} - {{pos_name}}, 
      "{{pred_name}}" := alpha.post / (alpha.post + beta.post) 
    ) %>%
    nest("{{param_name}}" := c(alpha, beta, alpha.post, beta.post))
}
######


#Takes in EITHER PLF Data or Pass_manifest and adds two column 
# - the eb_type of the row (data_pt)  (for now this is XX or XX* depending on grey_list)
# - whether the country is grey
#dt_col_name is column name containing the date of the corresponding data point (will be today_dt for pass_manifest)
#out_ctry_col_name is a column name for output column: either "isGrey" or "isCtryGrey" to maintain backwards compatibility
#END_OF_TIME is an arbitrary date larger than everything in dataset
label_eb_types<- function(dat, dt_col_name, out_ctry_col_name, END_OF_TIME = ymd("21210101")){
  #read in the grey_list data
  grey_list_se <- read_csv("../sample_input_data_fake/grey_list_start_end.csv",
                           col_types = cols(end_date = col_date()) ) %>%
    mutate(end_date = as_date( ifelse(is.na(end_date), END_OF_TIME, end_date) ))
  
  dat <- left_join(dat, grey_list_se, by="country") %>%
    mutate(data_pt_grey = start_date <= {{dt_col_name}} & {{dt_col_name}} <= end_date, 
           data_pt_grey = ifelse(is.na(data_pt_grey), FALSE, data_pt_grey), 
           eb_type = ifelse(data_pt_grey, str_c(country, "*"), country), 
           "{{out_ctry_col_name}}" := data_pt_grey
    ) %>%
    select(-data_pt_grey, -start_date, -end_date)
  return(dat)
}


#Takes in EITHER PLF Data or Pass_manifest and adds two column 
# - the eb_type of the row (data_pt)  which indicates city (if significant) and grey_listing
# - whether the country is grey
#dt_col_name is column name containing the date of the corresponding data point (will be today_dt for pass_manifest)
#out_ctry_col_name is a column name for ouput column: either "isGrey" or "isCtryGrey"
#END_OF_TIME is an arbitrary date larger than everything in dataset
label_eb_types_city<- function(dat, dt_col_name, out_ctry_col_name, END_OF_TIME = ymd("21210101")){
  #read in the grey_list data
  grey_list_se <- read_csv("../sample_input_data_fake/grey_list_start_end.csv",col_types = cols(end_date = col_date()) ) %>%
    mutate(end_date = as_date( ifelse(is.na(end_date), END_OF_TIME, end_date) ))
  
  #read in the cities with significant differences from country.  These are identified separately and stored
  city_types = read_csv("../sample_input_data_fake/city_types.csv") %>%
    mutate(country = str_to_upper(country), city = str_to_upper(city), 
           ctry_city = str_c(country,"_", city), 
           eb_type = ctry_city)
  
  #First go through and label the eb_type as either XX or XX_city if in the city types (neglecting grey-listing)
  dat <- dat %>% mutate(ctry_city = str_c(country, "_", city)) %>%
    left_join(., select(city_types, ctry_city, eb_type),  by="ctry_city") %>%
    mutate(eb_type = ifelse(is.na(eb_type), country, eb_type)) %>% 
    select(-ctry_city)
  
  #Now go through and back label anyone that was grey  
  dat <- left_join(dat, grey_list_se, by="country") %>%
    mutate(data_pt_grey = start_date <= {{dt_col_name}} & {{dt_col_name}} <= end_date, 
           data_pt_grey = ifelse(is.na(data_pt_grey), FALSE, data_pt_grey), 
           eb_type = ifelse(data_pt_grey, str_c(eb_type, "*"), eb_type), 
           "{{out_ctry_col_name}}" := data_pt_grey
    ) %>%
    select(-data_pt_grey, -start_date, -end_date)
  return(dat)
}






#####
#Clean the plf data
#  This involves a couple steps
#  - Renames Namibia (NA) to (NA_)  
#  - Back labels the type based on PCR status using historical testing protocols
#  - if flag = FALSE, use label_eb_types instead of label_eb_types_city 
#NOTE:  DOES NOT Clip the data based on date of entry!
clean_hist_plf_data <- function(plf_data, today_dt, log_file, use_city_types=TRUE){
  #Dangerous:  Namibia is stored as NA in iso_codes which confuses R.  Rename it to NA_
  plf_data <- mutate(plf_data, country = ifelse(is.na(country), "NA_", country))
  
  ### Grey-Listing
  #Back label points by their eb-type based on grey_list
  if(use_city_types){
    plf_data <- label_eb_types_city(plf_data, date_entry, isCtryGrey)
  }else{
    plf_data <- label_eb_types(plf_data, date_entry, isCtryGrey)
  }
  
  #White list needed to mark flagged countries in historical data
  ctry_white_list <- read_csv("../sample_input_data_fake/countries_allowed.csv", col_names=c("country"))
  
  plf_data <- plf_data %>% 
    mutate(
      to_test_raw = to_test, 
      sent_for_test_raw = sent_for_test, 
      test_result_raw = test_result, 
      to_test = ifelse(is.na(to_test), "not_seen", to_test),
      sent_for_test = ifelse( !is.na(test_result), TRUE, sent_for_test), 
      sent_for_test = ifelse(is.na(sent_for_test), FALSE, TRUE), 
      test_result = ifelse(is.na(test_result) & sent_for_test, "negative", test_result), 
      isCtryFlagged = ! country %in% ctry_white_list$country
    )
  
  return(plf_data)  
}

