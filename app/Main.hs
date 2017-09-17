{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

import CSV
import Control.Monad.Catch
import Control.Exception
import Control.Lens
import Control.Monad
import Control.Monad.Fix
import Data.Data
import Data.Foldable
import Data.Default
import Data.Monoid
import Data.Time
import Data.Yaml hiding ((.~))
import GHC.Generics hiding (to)
import System.FilePath.Posix
import qualified Data.Csv as CSV
import qualified Data.Csv as CSV
import qualified Data.List as DL
import qualified Data.Text as DT

type Amount = Double

type Rate = Int

data BadMergeException = BadMergeException String deriving (Eq,Ord,Show,Read,Data,Typeable)

data BudgetType = 
    Income 
  | Expense String
  deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

data Transaction = Transaction
  { _tDate :: Day
  , _tNo :: String
  , _tDesc :: String
  , _tDebit :: Maybe Amount
  , _tCredit :: Maybe Amount
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

makeLenses ''Transaction

data ExpenseItem = ExpenseItem
  { _date :: Day
  , _eAmount :: Amount
  , _reason :: String
  , _expenseType :: BudgetType
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

makeLenses ''ExpenseItem

data BudgetItem = BudgetItem 
  { _budgetType :: BudgetType
  , _rate :: Rate
  , _amount :: Amount
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

data Budget = Budget 
  { _name :: String
  , _startDate :: Day
  , _startAmount :: Amount
  , _items :: [BudgetItem]
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

makeLenses ''Budget

data Expenses = Expenses 
  { _eBudgetName :: String
  , _expenses :: [ExpenseItem]
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

makeLenses ''Expenses

data Bank = Bank
  { _checking :: Amount
  , _savings :: Amount
  , _lastModified :: Rate
  } deriving (Eq,Ord,Show,Read,Data,Typeable,Generic)

makeLenses ''Bank


instance CSV.FromRecord Transaction

instance CSV.ToRecord Transaction

instance Default BudgetType where
  def = Income

instance Default Day where
  def = fromGregorian 0 0 0

instance Default ExpenseItem 

instance Default Expenses 

instance Default BudgetItem 

instance Default Budget 

instance Default Bank 

instance Exception BadMergeException

instance FromJSON BudgetType where
  parseJSON (String s)
    | s == "income" = return Income
    | otherwise = return $ Expense (DT.unpack s)
  parseJSON _ = fail "Budget type is the wrong yaml type - should be a string"

instance FromJSON ExpenseItem

instance FromJSON Expenses

instance FromJSON BudgetItem

instance FromJSON Budget

instance FromJSON Bank

instance ToJSON ExpenseItem

instance ToJSON BudgetType where
  toJSON Income = String $ DT.pack "income"
  toJSON (Expense s) = String $ DT.pack s

instance ToJSON BudgetItem

instance ToJSON Budget

instance ToJSON Bank

instance ToJSON Expenses

amount :: Lens' BudgetItem Amount
amount = lens gt st
  where
    st s a = BudgetItem 
      { _amount = -1*(abs a)
      , _rate = _rate s
      , _budgetType = _budgetType s
      }
    gt = _amount

rate :: Lens' BudgetItem Rate
rate = lens gt st
  where
    st s r = BudgetItem 
      { _amount = _amount s
      , _rate = r
      , _budgetType = _budgetType s
      }
    gt = _rate

budgetType :: Lens' BudgetItem BudgetType
budgetType = lens gt st
  where
    st s t = BudgetItem 
      { _amount = _amount s
      , _rate = _rate s
      , _budgetType = t
      }
    gt = _budgetType


getExpense :: String -> Budget -> Maybe BudgetItem
getExpense n b = DL.find (isName . _budgetType) $ b^.items
  where
    isName Income = False
    isName (Expense t) = n == t

-- runs a budget for "p" periods given a starting amount "start" and returns the
-- final balance. 
getBalanceAtPeriod :: Rate -> Budget -> Amount
getBalanceAtPeriod p b = (b^.startAmount +) . getSum . mconcat . fmap sumItem $ b^.items
  where
    sumItem i = Sum $ (i^.amount)*(fromIntegral . floor . toRational $ p `div` (i^.rate))

printBalances :: Rate -> Budget -> IO ()
printBalances ds budget = sequence_ $ [printBal d | d <- [0..ds]]
  where
    printBal d = putStrLn $ 
         (show d)
      ++ ": "
      ++ (show $ getBalanceAtPeriod d budget)

getEmptyDate :: Budget -> Int
getEmptyDate budget = g 0
    where
      g n
        | (f n) <= 0 = n
        | otherwise = g (n+1)
      f n = getBalanceAtPeriod (n+1) budget

newIncome :: BudgetItem
newIncome = def

newExpense :: String -> BudgetItem
newExpense s = def & budgetType .~ (Expense s)

currentDay = utctDay <$> getCurrentTime

dayToRate :: Day -> Day -> Rate
dayToRate s = fromInteger . flip diffDays s

rateToDay :: Day -> Rate -> Day
rateToDay s = flip addDays s . toInteger

loadYamlFile :: (FromJSON a) => FilePath -> IO [a]
loadYamlFile fp = decodeFileEither fp >>= either throwIO return

currentBudgetBal :: Budget -> IO Amount
currentBudgetBal b = do 
  n <- currentDay 
  return $ getBalanceAtPeriod (dayToRate (b^.startDate) n) b

income = 1730.77 :: Amount
loanAmount = 11352.14 :: Amount

bank = def & checking .~ 3868.88 & savings .~ 1848.55

budgetLoan = def 
  & name .~ "Loan"
  & startDate .~ fromGregorian 2017 09 01
  & startAmount .~ loanAmount
  & items .~ 
    [newExpense "loan" 
      & amount .~ (income - (income*0.1 + income*0.2)) 
      & rate .~ 15 
    ]

budgetLiving = def
  & name .~ "Living"
  & startDate .~ fromGregorian 2017 09 01
  & startAmount .~ income
  & items .~ 
    [ newIncome & amount .~ 2000 & rate .~ 500
    , newIncome & amount .~ (income*0.1 + income*0.2) & rate .~ 15
    , newExpense "tithe" & amount .~ (income*0.1) & rate .~ 15
    , newExpense "taxes" & amount .~ (income*0.2) & rate .~ 15
    , newExpense "rent" & amount .~ 350 & rate .~  31
    , newExpense "auto" & amount .~  20 & rate .~ 7
    , newExpense "food" & amount .~ 20 & rate .~ 7
    , newExpense "insurance" & amount .~ 76 & rate .~ 31
    , newExpense "phone" & amount .~ 30 & rate .~ 31 
    , newExpense "climbing" & amount .~ 55 & rate .~ 31
    , newExpense "mentoring" & amount .~ 7 & rate .~ 31
    ]

loadTransactionFile :: FilePath -> IO [Transaction]
loadTransactionFile = loadCSVFile . ("transactions" </>)

transToExpenses :: (Foldable f) => String -> f Transaction -> Expenses
transToExpenses bname ts = def
  & eBudgetName .~ bname
  & expenses .~ exps 
  where
    exps = toExpense <$> (toList ts)
    toExpense t = def
      & date .~ (t^.tDate)
      & reason .~ (t^.tDesc)
      & eAmount .~ (c - d)
      & expenseType .~ case (c > 0) of
        True -> Income
        _ -> Expense ""
      where
        d = t^.tDebit . to num
        c = t^.tCredit . to num
        num = maybe 0 id

loadNewTransactionFile :: String -> FilePath -> IO ()
loadNewTransactionFile bName fp = loadTransactionFile fp 
  >>= encodeFile ("transactions" </> (fp) -<.> "yaml")
    . (:[])
    . (\es -> es & expenses %~ DL.sortOn _date) 
    . (transToExpenses bName)

mergeExpenses :: Expenses -> Expenses -> Expenses
mergeExpenses es1 es2 = es1 & expenses .~ mconcat (mergeDups pred mod ((:[]) <$> es1^.expenses) ((:[]) <$> es2^.expenses))
  where
    pred (a:[]) (b:[]) = (a^.date == b^.date) && (a^.eAmount == b^.eAmount)
    mod (a:[]) bs = (a & reason %~ (++" ?")) : bs

mergeDups :: (a -> a -> Bool) -> (a -> a -> a) -> [a] -> [a] -> [a]
mergeDups pred mod as bs = merges (as ++ bs)
  where
    merges [] = []
    merges (a:xs) = 
      let (as,bs) = DL.partition (pred a) xs
      in (merge (a:as)) : (merges bs)
    merge = foldr1 mod

mergeExpensesFiles :: FilePath -> FilePath -> IO ()
mergeExpensesFiles fp1 fp2 = do
  es1 <- loadYamlFile fp1 
  es2 <- loadYamlFile fp2
  let merged = mergeDups pred mergeExpenses es1 es2
  encodeFile (fp1 -<.> "" ++ "_merged.yaml") merged
  where
    pred a x = x^.eBudgetName == a^.eBudgetName 

main :: IO ()
main = do 
  bs <- loadYamlFile "budgets.yaml"
  es <- loadYamlFile "expenses.yaml" :: IO [Expenses] 
  now <- currentDay
  let
    budgetLoan = bs !! 0
    budgetLiving = (bs !! 1) & startAmount %~ (\x -> x-600)
    n = getEmptyDate budgetLoan
    x = getBalanceAtPeriod (n+1) budgetLoan
    m = getEmptyDate budgetLiving
    y = getBalanceAtPeriod (n+1) budgetLiving
  putStrLn $ "Loan can be payed off in: " 
    ++ (show n) 
    ++ " days - " 
    ++ (show . rateToDay (budgetLoan^.startDate) $ n) 
    ++ " - " ++ (show x)
  putStrLn $ "Your living budget will last: " 
    ++ (show m) 
    ++ " days - " 
    ++ (show . rateToDay (budgetLiving^.startDate) $ m) 
    ++ " - after loan: " ++ (show y)
  lo <- currentBudgetBal budgetLoan
  li <- currentBudgetBal budgetLiving
  putStrLn $ "Current balances should be: "
  putStrLn $ "  Living: " ++ (show $ lo)
  putStrLn $ "  Loan: " ++ (show $ li)
