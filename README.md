# EvaTargetedCovid19Testing
Open-Source code for Project Eva:  A Targeted Testing Protocol for Greece
----

<p align="center">
<img width="250" src="https://pressroom.usc.edu/files/2020/07/Greece-Covid-web.104655.jpg">
</p>
In the interest of reproducibility, this repository contains open-source code implementing the key *estimation* and *targeted testing* steps of the algorithm underlying Project Eva.  For policy makers and researchers seeking to implement similar systems, please feel free to reach out to the authors below for clarification or help.    

</br>
<p align="center">
  :warning: <strong> All sample data provided is SYNTHETIC </strong> :warning:
  </br>
  Inputs and outputs do not represent actual prevalence of Covid19 in Greece or any other nation.
</p>
</br>

## Citing this work
Team Eva is currently drafting a research paper with the mathematical details of these algorithms in addition to empirical evidence from the summer of 2020 on the effectiveness of Eva.  In the meantime, should you need to cite this work, we politely ask you use the following citation:

```
@misc{bdgv2020Covid19,
  title={Real-Time, Targeted COVID-19 Testing at the Greek Border},
  author={Bastani, Hamsa and Drakopoulos, Kimon and Gupta, Vishal and Vlachogiannis, Jon},
  url={https://github.com/vgupta1/EvaTargetedCovid19Testing/}
  note={Open-Source Software}
}
```

## About Team Eva
Team Eva consists of 4 core members:
* [Hamsa Bastani](https://hamsabastani.github.io/), The Wharton School, U. of Pennysylvania 
* [Kimon Drakopoulos](https://www.kimondrakopoulos.com/), USC Marshall School of Business
* [Vishal Gupta](http://faculty.marshall.usc.edu/Vishal-Gupta/), USC Marshall School of Business
* [Jon Vlachogiannis](https://www.linkedin.com/in/johnvlachoyiannis/), Founder of Agent Risk and Software Architect

Please feel free to reach out to Vishal Gupta above for questions/clarifications on the repository. 


## Background on Project Eva
Project Eva is a real-time, targeted testing protocol that we deployed in Greece over the summer of 2020.  The full protocol involves a system in which 
 1. Potential travelers fill out a PLF Form at least 24 hours in advance of travel 
 2. Information from this PLF form is used to target a small fraction of travelers for testing upon arrival, subject to testing budget constraints at the various 41 points of entry.  These budgets are determined by the Greek Ministry of Health.  
 3. Tested travelers are asked to self-quarantine until results return
 3. Samples from travelers that are tested are processed by a lab in (at most) 48 hours 
 4. Travelers that are found to be positive are quarantined and contact tracing begins
 5. All results are fed back into the system to update estimates and targeting procedures for future travelers
In this way, the system is "closed-loop" and updates constantly as the state of the world evolves.  
 
Necessarily, in addition to the underlying mathematical algorithm, Eva involves integrating many databases across multiple government agencies, securely handling sensitive information, and coordinating databases in nearly real time.  This repository _only_ contains code related to the actual estimation of prevalence and targeting algorithms.  In deployment (and here) it works only with anonymized data.  (The data used here is again synthetic and not representative of actual prevalence rates.)   

For more details on Project Eva, please see:
* [USC Press Release on Project Eva](https://pressroom.usc.edu/reopen-greek-economy/)
* [Webinar with Kimon and Vishal](https://www.marshall.usc.edu/news/project-eva-ai-covid-and-greek-tourism)
* [Algorithm Overview with Hamsa](https://www.youtube.com/watch?v=I_OUdIih_00&feature=emb_title&ab_channel=SimonsInstitute)

## Overview of Algorithm
As mentioned, the authors are currently drafting research publications documenting Eva's mathematical details.  At a high level, the underlying algorithm estimates the prevalence of infections from different locations, and allocates tests using a specialized multi-armed bandit algorithm.

### Estimating Prevalences using Empirical Bayes
<img align="right" width="600" src="https://github.com/vgupta1/EvaTargetedCovid19Testing/blob/main/sample_outputs/eb_estimates_by_cntry.png?raw=true">
We define "types" of travelers, and use testing data from the recent past to estimate the COVID19 prevalence for each type via an Empirical Bayes methodology.  In contrast to traditional parametric empirical Bayes approaches using a beta-prior, we use a mixture prior informed by features of the various traveler types.  Updates with this prior are straightforward, and yield beta posteriors for each traveler type.  These estimates are used to inform various dashboards (not included in repository), including, e.g., the one at right (included in *sample_outputs*). 

The model and algorithm allow for very granular definitions of "type" (e.g., men from Los Angeles, CA, USA between the age of 30-40 traveling alone who have not visited any other countries in last 2 weeks); in practice, we found that only passengers' origin location was predictive of prevalence. Thus, we define passenger types as the country of origin for _most_ passengers. Clearly, including more types (e.g., defining passenger locations based on the origin city) will allow a richer parametrization of prevalence estimates, but it also causes higher variance in our estimates since there are thousands of origin cities. To address this bias-variance tradeoff, we use recent testing data to fit a LASSO logistic regression to identify a *sparse* subset of cities that demonstrate systematically higher prevalence after conditioning on the empirical bayes estimate of the origin country. Such cities are broken out as separate types from their parent country (listed in *city_types.csv*). We updated this regression weekly to adapt to recent testing data.

The prior was defined as mixture prior, with 3 beta components, for each of
  1. "Black-listed" types for countries not on the *countries_allowed.csv* list (discussed below)
  2. "Grey-Listed" types from countries for which a negative PCR test was required prior to travel and 
  3. "White-listed" types for the remainder.  Sample code in this repository follows this structure.


### Testing Allocations using Multi-Armed Bandits
When allocating tests, we must balance allocating tests across all types to monitor the progression of prevalence in different locations (exploration), and allocating tests to the types with the highest prevalence to maximize the number of infected passengers identified (exploitation). We customize a classic bandit algorithm (a one-step lookahead approximation to the Gittins index) to balance this exploration-exploitation tradeoff. Our algorithm additionally accounts for
1. Nonstationarity: the prevalence in any location is rapidly evolving during the course of the pandemic,
2. Batched decision-making: all testing allocations must be made at the start of the day due to operational constraints,
3. Delayed feedback: lab test results require two days to be received,
4. Port-specific testing constraints: different ports have different passenger arrival mixes and testing budgets.

First, to address nonstationarity, we use a 2-week rolling window of testing data for all prevalence estimates. Next, traditional batched bandit algorithms follow an explore-then-commit strategy, and thus are not appropriate in highly nonstationary environments where one must weave exploration and exploitation within the same batch. Thus, we perform *certainty-equivalent updates* when a test is allocated to a passenger, essentially simulating the reduction in the variance of our posterior estimates by performing a single test. Within a batch, this approach allows us to allocate a sufficient number of tests to resolve variance for each type (exploration) and allocate the remaining tests to types with high prevalence (exploitation). Delayed feedback is naturally accounted for by additionally performing certainty-equivalent updates for any tests that have been performed but whose results have not yet been received. Lastly, due to port-specific constraints, we may wish to "save tests" at ports with low testing budgets that receive unique passenger types. We employ a greedy heuristic to ensure that we allocate tests at the least constrained port (as measured by remaining testing capacity) when possible. Our testing budgets also account for the (sometimes significant) incidence of "no-shows" (passengers who are scheduled to arrive who cancel their trip last minute).

In a typical batch, we assign aproximately 8K tests to approximately 60K potential passengers. (The sample data provided is smaller than these representative numbers).  


## Structure of Repository
Code is written in R and located in the folder _src/_. The code is written in R and is mostly easily accessed via the R-Studio Project included in the folder.  
 - _dailyRun.r_ executes the empirical bayes fitting and bandit allocation described above.  All outputs are written to _/sample_outputs/_  
 - _featureCheck.R_ performs the analysis above to identify potentially significant additional types to add.  This file requires that dailyRun.r was run previously before running as it uses outputs from _/sample_outputs/_ in the procedure.

This algorithm references various data sources in the folder *sample_input_data_fake/*.  In deployment, these data sources are populated by Eva's backend databases with realtime data from the last 16 days (*hist_db_working.csv*) and all travelers scheduled to arrive tomorrow (*pass_manifest.csv*).  The remaining files are "static data" that is updated periodically in consultation with the Greek Government Covid19 Taskforce, including
 - *port_budgets.csv* : The number of tests available at each port of entry on a daily basis.
 - *countries_allowed.csv* : The list of countries that are permitted to travel to Greece.  This list is developed in conjuction with the European Union.
 - *grey_list_start_end.csv* : Travelers from these countries are required to demonstrate a negative PCR test before travel.  This list is updated periodically in consultation with the Greek Government Covid19 Taskforce based on Eva's estimates of Covid19 Prevalence and public data on reported cases.  
 - *city_types.csv* : As discussed above, a list of special cities to be treated separately when defining types. 

Again, we stress that the data provided in this repository are synthetic.




