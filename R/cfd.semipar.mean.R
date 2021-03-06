#'
#' @title Mean Decomposition: semiparametric version
#'
#' @description Decompose the mean difference in outcome Y between groups. In this semiparametric version, we do not assume a parametric model for the mediator: instead, we sample from the distribution of the mediator in the reference group; this can be done within strata of one or more third variables.
#'
#' @param formula the \code{\link{formula}} for the multivariable model (see \code{\link{glm}}) for the outcome Y.
#' @param mediator the column name of the mediator M.
#' @param group column name of the variable containing the group identifier.
#' @param strata the name of a variable containing the strata of a third variable (or set of variables) within which we equalize mediator values. Ideally this is a factor variable.
#' @param nbin if a numeric (i.e. non-factor or character) strata variable is defined, how many bins should be made from it within which we equalize the mediator distribution?
#' @param data a data frame containing the variables in the model.
#' @param family a description of the error distribution to be used in the model, see \code{\link{family}} for details. For the outcome variable any member of the \code{glm} family can be used.
#' @param bs.size the number of bootstrap iterations to be performed.
#' @param mc.size the number of Monte Carlo iterations to be performed (more = more MC error reduction).
#' @param alpha the alpha level used to construct confidence intervals (0.05 = 95 percent confidence interval).
#' @param print.iteration print the bootstrap iteration
#'
#' @return \code{out_nc} returns the mean level of the outcome under the natural course, which is a value that should be close to the empirically observed value of the outcome for each group. \code{out_nc_quantile} provides the \code{alpha/2} and \code{1-alpha/2} bootstrap quantiles for this mean (AKA bootstrap percentile confidence intervals).Similarly, \code{out_cf}, \code{out_cf_quantile},provide the corresponding values for the counterfactual scenario where the mediators of the groups are equalized. \code{mediation} returns the proportion mediated by setting the intervened on mediator to be equal in level to the reference group and \code{mediation_quantile} returns the 1-alpha confidence interval.
#' @export
#' @examples
#' set.seed(100)
#' # the decomposition functions in our package are computationally intensive
#' # to make the example run quick, I perform it on a subsample (n=250) of the data:
#' cfd.example.sample <- cfd.example.data[sample(250),]
#' mean.semipar.results.1 <- cfd.semipar.mean(formula='out.gauss ~ SES + med.gauss + med.binom + age',
#'                                           mediator='med.gauss',
#'                                           group='SES',
#'                                           strata='age',
#'                                           nbin=5,
#'                                           data=cfd.example.sample,
#'                                           family='gaussian',
#'                                           bs.size=50,
#'                                           mc.size=10,
#'                                           alpha=0.05)
#' # also note that normally we would recommend an bs.size of 250+
#' # and an mc.size of 50+
#' # see README.md for a more detailed description of the functions in this package.
#' @import stats
cfd.semipar.mean <- function(formula,mediator,group,strata=NA,nbin=5,
                             data,
                             family = 'binomial',
                             bs.size = 1000,
                             mc.size=50,
                             alpha=0.05,
                             print.iteration=FALSE) {

  ## envir check
  call <- match.call()
  if (is.character(family))
    family <- get(family, mode = "function", envir = parent.frame())
  if (is.function(family))
    family <- family()
  if (is.null(family$family)) {
    print(family)
    stop("'family' not recognized")
  }
  if (missing(data))
    data <- environment(formula)
  mf <- match.call(expand.dots = FALSE)

  ## get initial fit
  ini_fit <- glm(formula = formula,
                 data=data, family=family)
  ini_fit$model_matrix <- model.matrix(as.formula(formula), data = data)

  fam <- family(ini_fit)

  ## loop over bootstrap samples
  out_nc <- matrix(NA,nrow=bs.size,ncol=nlevels(data[,group]),dimnames = list(1:bs.size,levels(data[,group])))
  out_cf <- matrix(NA,nrow=bs.size,ncol=nlevels(data[,group]),dimnames = list(1:bs.size,levels(data[,group])))

  ## temp matrix to save mc results
  temp <- matrix(NA, nrow=mc.size, ncol=nlevels(data[,group]))

  for(i in 1:bs.size) {
    if(print.iteration==TRUE){print(i)}

    ## resampling
    resample_ind <- sample(nrow(data), replace=TRUE)
    data_bs <- data[resample_ind,]

    ## refit model
    bs_fit <- update(ini_fit, data = data_bs)
    coef_bs <- coef(bs_fit)

    ##
    pred_bs <- predict(bs_fit,data_bs,type='response')

    # ! Note that this function predicts means only because it compares means
    # ! Hence the entire distribution of values is not re-created
    # ! If that is desired, see the function for the quantiles instead.
    out_nc[i,] <- tapply(pred_bs, list(data_bs[,group]),mean,na.rm=TRUE)

    ####
    ##
    if(is.na(strata)){
      strata_grp <- rep(1,nrow(data_bs))
      data_bs_grp <- data_bs[,c(mediator,group)]
    }
    ##
    if(!is.na(strata)){
      data_bs_grp <- data_bs[,c(mediator,group,strata)]
      for(v in strata){
        if(is.numeric(data_bs_grp[,v])){
          # if the strata variable is a factor, nothing needs to be done to it
          # but if the strata variable is numeric, we need to make categories in which to equalize the mediator
          if(length(unique(data_bs_grp[,v])) > 20)
            data_bs_grp[,v] <- cut(data_bs_grp[,v], breaks=c(quantile(data_bs_grp[,v], probs = seq(0, 1, by = 1/nbin))), include.lowest=TRUE)

          if(length(unique(data_bs_grp[,v])) <= 20)
            data_bs_grp[,v] <- factor(data_bs_grp[,v])
        }
      }
      strata_grp <- do.call(paste,as.list(data_bs_grp[c(strata)]))
    }

    ## make the mediator * group distribution equal across strata
    ref_level <- levels(data_bs[,group])[1]
    ind <- list()
    for(lv in unique(strata_grp)){
      ind_ref   <- data_bs_grp[,group] == ref_level & strata_grp == lv
      ind_other <- data_bs_grp[,group] != ref_level & strata_grp == lv
      ind[[lv]] <- list(ind_ref=ind_ref,ind_other=ind_other)
    }

    data_bs_mc <- data_bs
    for(ii in 1:mc.size){
      ## make the mediator * group distribution equal across strata
      for(lv in unique(strata_grp)){
        data_bs_mc[ind[[lv]]$ind_other,mediator] <- sample(data_bs[ind[[lv]]$ind_ref,mediator],sum(ind[[lv]]$ind_other),replace = T)
      }

      pred_bs_mc_counterfactual <- predict(bs_fit,data_bs_mc,type='response')
      temp[ii,] <-  tapply(pred_bs_mc_counterfactual, list(data_bs_mc[,group]),mean,na.rm=TRUE)

    }
    ##
    out_cf[i,] <- apply(temp,2,mean,na.rm=TRUE)

  }
  return(list(out_nc=out_nc,
              out_cf=out_cf,
              out_nc_quantile=apply(out_nc,2,quantile,c(alpha/2,0.5,1-alpha/2)),
              out_cf_quantile=apply(out_cf,2,quantile,c(alpha/2,0.5,1-alpha/2)),

              mediation=apply(1-(out_cf - out_nc[,1]) / (out_nc - out_nc[,1]),2,mean)[-1],
              mediation_quantile=apply(1-(out_cf - out_nc[,1]) / (out_nc - out_nc[,1]),2,quantile,probs=c(alpha/2,1-alpha/2),na.rm=TRUE)[,-1]
  )
  )
}
