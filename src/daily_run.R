#### 
#  Simplified Version of Daily Bandit for Test Allocation
####
# For the purposes of reproducibility and code sharing, this file runs our fitting and bandit procedure on some sample data
# Sample data has been suitably anonymized.  Values do NOT represent actual data from Greece. 
# For simplicity, this code works with cleaned sample data (hence doesn't check inputs) and produces minimal outputs
# Actual users will likely add additional code for data-wrangling and post-processing outputs for dashboards.  
library(tidyverse)
library(lubridate)
source("helpers_public.R")
source("Bandit_Public.R")

##CONSTANTS
gittins.discountFact = .9
log_file = "log.txt"
MIN_TEST = 0  #Only countries with at least this many tests are used in the prior fitting.  A value of 50 was used in deployment

cat("Starting Log File\n ", file=log_file)

### 
# Passenger manifest  
today_dt <- ymd("2020-09-01")
pass_manifest <- read_csv("../sample_input_data_fake/pass_manifest.csv") %>%
                  mutate(dt_entry = today_dt) 
pass_manifest <- label_eb_types_city(pass_manifest, dt_entry, isGrey) %>% select(-dt_entry)


######
# PLF data
plf_data <- read_csv("../sample_input_data_fake/hist_db_working.csv", 
                     col_types = cols( result_id = col_double(),
                                       country = col_character(),
                                       city = col_character(),
                                       date_entry = col_date(format = ""),
                                       point_entry = col_character(),
                                       to_test = col_character(),
                                       test_result = col_character(),
                                       sent_for_test = col_double()
                     ))

plf_data <- clean_hist_plf_data(plf_data, today_dt, log_file)


#Keep track of the tests that were done in the last 48 hours so bandit can adjust
testing_last_48 <- plf_data %>% 
  filter(date_entry <= today_dt, date_entry > today_dt - 2) %>%
  group_by(eb_type) %>%
  summarise(tests_last_48 = sum(sent_for_test))

#Now clip 48 hours (for testing result delays)
plf_data <- plf_data %>% filter(date_entry <= today_dt - 2) 

# These are determined through discussions with Greek COVID Taskforce  and testing labs offline, outside of system
port_budgets <- read_csv("../sample_input_data_fake/port_budgets.csv")

#Adjust budgets for flagged people, and mark flagged COUNTRIES in the manifest
t <- adjust_budgets(pass_manifest, port_budgets, log_file=log_file)
port_budgets <- t[[1]]
pass_manifest <- t[[2]]
rm(t)


#######
### An Auxiliary Output for daily monitoring of Ops and Dashboards
{
  #Table by entry point of what was supposed to be tested and what was tested
  testing_past_week <- plf_data %>% 
    filter(date_entry >= today_dt  - 9) %>%
    group_by(point_entry, date_entry) %>%
    summarise( numMarked = sum(to_test == "true"), 
               numFlagged = sum(to_test == "flag"),
               numSent = sum(sent_for_test)
    )
  
  #add the budgets for easy comparison
  testing_past_week <- left_join(testing_past_week, 
                                 select(port_budgets, Entry_point, Target_Capacity, Capacity), 
                                 by=c("point_entry"="Entry_point")  ) %>%
    mutate(numToTest = ifelse(Target_Capacity <= 0, numMarked, numMarked + numFlagged)) %>%
    select(point_entry, date_entry, numMarked, numFlagged, numToTest, numSent, Target_Capacity, Capacity)
  
  ##write it twice, for archive and for using
  write_csv(testing_past_week, 
            paste("../sample_outputs/test_summary_by_port_last_week_", today_dt, ".csv", sep="")
  )
  rm(testing_past_week)
}


#####
#  Summarizing Data for Bandit
####
hist_data <- plf_data %>% group_by(eb_type, isCtryFlagged, isCtryGrey) %>%
  summarise( num_arrivals = n(), 
             num_tested = sum(sent_for_test), 
             num_pos = sum(test_result == "positive", na.rm=TRUE), 
             num_inconclusive = sum(!is.na(test_result) & !test_result %in% c("positive", "negative"))
  )


#add back people on the Passenger Manifest that we've never seen historically
hist_data <- 
  full_join(hist_data, 
            unique(select(pass_manifest, eb_type, cntry_flagged, isGrey)), by="eb_type") %>%
  mutate(num_arrivals = ifelse(is.na(num_arrivals), 0, num_arrivals), 
         num_pos      = ifelse(is.na(num_pos), 0, num_pos), 
         num_tested   = ifelse(is.na(num_tested), 0, num_tested), 
         num_inconclusive = ifelse(is.na(num_inconclusive), 0, num_inconclusive), 
         isCtryFlagged = ifelse(is.na(isCtryFlagged), cntry_flagged, isCtryFlagged),  #take from the pass manifest
         isCtryGrey = ifelse(is.na(isCtryGrey), isGrey, isCtryGrey)  #take from pass_manifest
  ) %>%
  select(-isGrey, -cntry_flagged) #drop superfluous columns from pass_manifest

#tack on all the testing in the last 48 hours
hist_data <- left_join(hist_data, testing_last_48) %>%
  mutate(tests_last_48 = ifelse(is.na(tests_last_48), 0, tests_last_48))


######
# EB Fitting
#####
#Fit the EB models fitting mixture prior distribution
# Only use countries with > MIN_TEST tests when fitting prior
# Fit separate priors for different testing protocols
hist_data <- mutate(hist_data, prev = num_pos/num_tested) %>% ungroup() 

##White-listed countries
t_moments <- hist_data %>% filter(num_tested >= MIN_TEST, 
                                  !isCtryFlagged, !isCtryGrey) %>%  
  summarise(mom1 = mean(prev, na.rm=TRUE), 
            mom2 = mean( prev * (num_pos-1)/(num_tested-1), na.rm=TRUE)
  )

#Moment matching might fail.  These default values are tuned manually and updated periodically
if(t_moments$mom1 <= t_moments$mom2  | t_moments$mom2 <= t_moments$mom1^2){
  cat("\n \n Whitelist MOMENT MATCHING PROCEDURE FAILED.  Default values.", file=log_file, append=TRUE)
  t_moments$mom1 = 0.00612
  t_moments$mom2 = 0.0000593
}

##Use the blacklist countries to fit separate moments
t_moments_black <- hist_data %>% filter(num_tested >= MIN_TEST, 
                                        isCtryFlagged) %>%
  summarise(mom1 = mean(prev, na.rm=TRUE), 
            mom2 = mean( prev * (num_pos-1)/(num_tested-1), na.rm=TRUE)
  )

#Moment matching might fail.  These default values are tuned manually and upated periodically
if(t_moments_black$mom1 <= t_moments_black$mom2  | t_moments_black$mom2 <= t_moments_black$mom1^2){
  cat("\n \n Black-list MOMENT MATCHING PROCEDURE FAILED", file=log_file, append=TRUE)
  t_moments_black$mom1 = 0.00678
  t_moments_black$mom2 = 0.0001
}

##Use the greylist countries to fit separate moments
t_moments_grey <- hist_data %>% filter(num_tested >= MIN_TEST, isCtryGrey) %>%  
  summarise(mom1 = mean(prev, na.rm=TRUE), 
            mom2 = mean( prev * (num_pos-1)/(num_tested-1), na.rm=TRUE)
  )

#Moment matching might fail.  These default values are tuned manually and upated periodically
if(t_moments_grey$mom1 <= t_moments_grey$mom2  | t_moments_grey$mom2 <= t_moments_grey$mom1^2){
  cat("\n \n Grey-list MOMENT MATCHING PROCEDURE FAILED", file=log_file, append=TRUE)
  t_moments_grey$mom1 = 0.00487
  t_moments_grey$mom2 = 0.0000419
}

#Update moments of black/grey
hist_data <- hist_data %>% 
  mutate( mom1 = ifelse(isCtryFlagged, t_moments_black$mom1, t_moments$mom1), 
          mom2 = ifelse(isCtryFlagged, t_moments_black$mom2, t_moments$mom2),
          mom1 = ifelse(isCtryGrey & !isCtryFlagged, t_moments_grey$mom1, mom1),    
          mom2 = ifelse(isCtryGrey & !isCtryFlagged, t_moments_grey$mom2, mom2)
  )
rm(t_moments, t_moments_black, t_moments_grey)

hist_data <- hist_data %>%
  fit_eb_MM(mom1, mom2, MM) %>%
  add_eb_preds(eb_prev, MM, num_pos, num_tested) %>%
  unnest(MM)

#redefine and reorder country as a factor in decreasing order of pred prev for later
#makes the plots look nice. :)
hist_data <- hist_data %>%
  mutate(eb_type = factor(eb_type), 
         eb_type = fct_reorder(eb_type, .x = eb_prev, .desc = TRUE) 
  )

# Generate the current_estimates output
curr_estimates <- 
  hist_data %>% select(eb_type, isCtryFlagged, isCtryGrey, eb_prev, prev, num_pos, num_tested, num_arrivals, alpha.post, beta.post) %>%
  mutate(low = qbeta(.05, alpha.post, beta.post), 
         up  = qbeta(.95, alpha.post, beta.post)
  )

##write for archival puruposes and to be used be "feature_check_public.R"
write_csv(curr_estimates, 
          paste("../sample_outputs/country_estimates_", today_dt, ".csv", sep="")
)

# Generate some other auxiliary output for plots
# This code is seemingly complicated to make plots look pretty
# But is not crucial to the testing allocation by bandit
{
  #Generate the pretty plot.
  g <- curr_estimates %>% filter(!isCtryFlagged) %>% 
    ggplot(aes(eb_type, eb_prev * 1000,  ymin=low * 1000, ymax=up * 1000)) + 
    geom_point(aes(color=num_arrivals > 0)) + 
    geom_errorbar() + theme_bw() + 
    ylab("Cases per Thousand") + xlab("(Ordered by EB Prev)") + 
    labs(title = "EB Prevalence Estimates", caption=str_c("Whitelist only: ", today_dt)) + 
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1), 
          legend.position = "none")
  g
  ggsave("../sample_outputs/eb_estimates_by_cntry.pdf", 
         height=3, width=7, units="in")
  
  #Generate the testing allocations as tables
  total_tests = sum(hist_data$num_tested)
  dat.testing <- hist_data %>%
    mutate(prop_of_tests = num_tested/total_tests) %>%
    arrange(desc(num_tested))
  write_csv(dat.testing, 
            paste("../sample_outputs/recent_testing_", today_dt, ".csv", sep="")
  )
  
  #Testing Allocations as a plot
  g <- dat.testing %>% filter(!isCtryFlagged) %>%
    ggplot(aes(eb_type, prop_of_tests)) + 
    geom_col() + theme_bw()  + 
    scale_y_continuous(labels = scales::percent) + 
    labs(title="Recent Testing Allocation", caption=today_dt) +
    ylab("(%) of Total Testing") + xlab("(Ordered by Prev.)") + 
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1))
  g
  ggsave("../sample_outputs/recent_testing_alloc.pdf", 
         height=3, width=7, units="in")
  rm(dat.testing)
}  
#####

cat("\n \n -----Starting Gittins. -----\n ", file=log_file, append=TRUE)
#####
#Compute new testing allocations via Deferred-Acceptance Alg.
#####
#pass to bandit to do the real work.  
#only pass non-flagged passengers as well as columns needed by bandit
temp.manifest <- pass_manifest %>% filter(!cntry_flagged) %>%
  select(id, eb_type, point_entry)
temp.hist_data <- hist_data %>% filter(!isCtryFlagged) %>% 
  select(eb_type, alpha.post, beta.post, num_tested, tests_last_48)
temp.port_budget <- port_budgets %>% select(-Capacity)

#Bandit code seems to have some issue with tibbles, so pass as data.frame for now
today_testing <- gittinsBandit(as.data.frame(temp.manifest), 
                               as.data.frame(temp.port_budget), 
                               as.data.frame(temp.hist_data), 
                               gittins.discountFact)

rm(temp.port_budget, temp.hist_data, temp.manifest)
cat("\n \n -----Ending Gittins. -----\n ", file=log_file, append=TRUE)

#Marry bandit results to the flagged people and output
today_testing <- as_tibble(today_testing)
today_testing$flagged <- FALSE

pass_manifest <- left_join(pass_manifest, today_testing, by="id")

#Write outputs as needed for actual system
pass_manifest <- pass_manifest %>%
  mutate(flagged = ifelse(cntry_flagged, TRUE, flagged), 
         flagged = ifelse(isGrey & to_test, TRUE, flagged),  #how we signal to border agents to test PCR people
         to_test = ifelse(cntry_flagged, TRUE, to_test)
  )


##Write down the outputs for everyone else!
pass_manifest %>% select(id, to_test, flagged) %>%
  write_csv(paste("../sample_outputs/test_results_", today_dt, ".csv", sep=""))

###The next part of the script dumps some useful tables and pictures to assess Gittins and allocations
{
  #Now double check how many people you are testing makes sense for today's allocation
  #First by country, to assess Gittins. For this, focus on white_list only
  test_alloc_country <- pass_manifest %>% filter( !cntry_flagged ) %>%
    group_by(eb_type) %>%
    summarise( numArrived = n(), numMarked = sum(to_test), fracMarked = numMarked / n() )
  
  #reorder the countries in terms of decreasing eb_prev so that they look nice in terms on plots
  test_alloc_country <- left_join(test_alloc_country, select(curr_estimates, eb_type, eb_prev)) %>%
    mutate(eb_type = factor(eb_type), 
           eb_type = fct_reorder(eb_type, .x = eb_prev, .desc = TRUE))
  
  #Save it down
  write_csv(test_alloc_country, 
            paste("../sample_outputs/test_alloc_per_country_", today_dt, ".csv", sep="")
  )
  
  
  #do a cute graph with numArrivals and tested on overlapping
  g <- test_alloc_country %>%
    mutate(notTested = numArrived - numMarked) %>%
    gather("type", "num", notTested, numMarked) %>%
    ggplot(aes(eb_type, num, group=type, fill=type)) + geom_col() +
    theme_bw() + xlab("") + ylab("No. PLFs") +
    labs(title = "Test Allocation vs Arrivals", caption=str_c("(Whitelist Only) \n", today_dt)) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1),
          legend.position="none")
  g
  ggsave(str_c("../sample_outputs/test_alloc_vs_arrivals_by_country_", today_dt, "_.pdf"),
         height=3, width=7, units="in")
  
  rm(test_alloc_country)
  
}

cat("\n \n -----Run completed. -----\n ", file=log_file, append=TRUE)

