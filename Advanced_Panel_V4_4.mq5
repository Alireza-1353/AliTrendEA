//+------------------------------------------------------------------+
//|                                           FullAdvancedPanelEA.mq5|
//|                                  Copyright 2026, Trading Expert |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Trading Expert"
#property link      "https://www.mql5.com"
#define  EA_VERSION  "4.4"
#property version   EA_VERSION
#property strict

#include <Trade\Trade.mqh>

//--- انواع روش‌های مدیریت حجم
enum ENUM_LOT_TYPE
  {
   LOT_TYPE_FIXED,   // حجم ثابت (Fixed Lot)
   LOT_TYPE_RISK     // درصد ریسک از حساب (Risk Percent)
  };

//--- مدهای محاسباتی
enum ENUM_CALC_MODE
  {
   MODE_POINTS,
   MODE_USD,
   MODE_PERCENT
  };

//--- ورودی‌های اصلی اکسپرت
input group "=== تنظیمات عمومی معاملات ==="
input ulong          InpMagicNumber          = 123456;
input bool           InpPreventMulti         = true;

input group "=== مدیریت حجم و ریسک ==="
input ENUM_LOT_TYPE  InpLotType              = LOT_TYPE_FIXED;
input double         InpLotSize              = 0.10;
input double         InpRiskPercent          = 2.0;

input group "=== تنظیمات حد سود و ضرر و مدیریت پوزیشن ==="
input bool           InpUseSL                = true;
input double         InpStopLoss             = 200;
input bool           InpUseTP                = true;
input double         InpTakeProfit           = 400;
input bool           InpUseBreakEven         = true;
input double         InpBreakEvenTrigger     = 150;
input double         InpBreakEvenOffset      = 20;
input bool           InpUseTrailingStop      = true;
input double         InpTrailingStop         = 200;
input double         InpTrailingStep         = 50;

input group "=== تنظیمات هشدار صوتی ==="
input bool           InpEnableSoundAlert     = true;
input string         InpSoundFileName        = "alert.wav";

input group "=== تنظیمات خط روند ==="
input string         InpTrendlineName        = "ali";
input string         InpAutoTrendlinePrefix  = "Ali";     // پیشوند نام‌گذاری خودکار خطوط (Ali_1, Ali_2, ...)
input int            InpTolerancePoints      = 30;
input bool           InpInitialTLState       = true;

input group "=== هج خودکار در ضرر (Auto-Hedge) ==="
input bool           InpUseAutoHedge         = false;     // فعال/غیرفعال کردن هج خودکار
input double         InpAutoHedgeLossUSD     = 50.0;      // آستانه ضرر (به ارز حساب) برای باز کردن پوزیشن مخالف

input group "=== ردیف تشخیص روند چندتایم‌فریمی (M5/M15/M30/H1) ==="
input int            InpTrendEMAFast         = 50;        // دوره EMA میان‌مدت
input int            InpTrendEMASlow         = 200;        // دوره EMA اصلی
input int            InpTrendADXPeriod       = 14;         // دوره ADX
input double         InpTrendADXThreshold    = 20.0;       // آستانه ADX برای تایید قدرت روند

//--- متغیرهای سراسری متاتریدر
string g_gvLotKey, g_gvSLKey, g_gvTPKey, g_gvBEKey, g_gvBEOffsetKey, g_gvTSKey, g_gvTSStepKey;
string g_gvXKey, g_gvYKey, g_gvTLStateKey, g_gvMinKey, g_gvModeKey;
string g_gvUseSLKey, g_gvUseTPKey, g_gvUseBEKey, g_gvUseTSKey;
string g_gvUseHedgeKey, g_gvHedgeLossKey, g_gvTLCounterKey;

//--- متغیرهای سراسری پنل
double g_panelLot, g_panelSL, g_panelTP, g_panelBE, g_panelBEOffset, g_panelTS, g_panelTSStep;
bool   g_useSL = true, g_useTP = true, g_useBE = true, g_useTS = true;
int    g_panelX = 30, g_panelY = 40;
bool   g_trendlineActive = true, g_isMinimized = false; 
ENUM_CALC_MODE g_calcMode = MODE_POINTS;

//--- متغیرهای هج خودکار (Auto-Hedge)
bool     g_useHedge = false;
double   g_panelHedgeLoss = 50.0;
ulong    g_hedgedTickets[];      // تیکت‌هایی که قبلاً هج (قفل) شده‌اند تا دوباره پردازش نشوند

//--- انتخاب دستی پوزیشن روی چارت برای فعال/غیرفعال کردن BE و Trailing Stop به‌صورت مجزا برای هر پوزیشن
ulong    g_selectedPositionTicket = 0;   // تیکت پوزیشنی که با کلیک روی چارت انتخاب شده (0 = هیچ‌کدام)
ulong    g_beTsExcludedTickets[];        // تیکت‌هایی که کاربر دستی BE/Trailing را برایشان خاموش کرده (پیش‌فرض همه فعال هستند)
string   g_gvBeTsExclCountKey, g_gvBeTsExclPrefix; // کلیدهای GlobalVariable برای ماندگاری این لیست بین ری‌استارت‌های EA/ترمینال

//--- متغیرهای خطوط روند ساخته‌شده توسط اکسپرت (Ali_1, Ali_2, ...)
int      g_trendlineCounter = 0;
struct STLState
  {
   string   name;
   datetime lastBarTime;
  };
STLState g_tlStates[];

//--- وضعیت رسم دستی خط جدید با دو کلیک (Requirement: بدون ظاهر شدن خودکار خط)
int      g_tlDrawStage = 0;      // 0 = غیرفعال، 1 = منتظر کلیک نقطه شروع، 2 = منتظر کلیک نقطه پایان
datetime g_tlDrawT1    = 0;
double   g_tlDrawP1    = 0;

//--- متغیرهای جابه‌جایی و کنترل
bool     g_isDragging = false;
int      g_dragOffsetX = 0, g_dragOffsetY = 0;

const int PANEL_WIDTH  = 230;
const int PANEL_HEIGHT = 598;  // شامل ردیف روند M5/M15/M30/H1 + ردیف انتخاب پوزیشن برای BE/TS، بدون فضای اضافه
const int HEADER_HEIGHT = 25;

CTrade trade;

//--- تعاریف اشیاء گرافیکی
#define PREFIX          "ADV_EA_"
#define PANEL_BG        PREFIX "Bg"
#define PANEL_HEADER    PREFIX "Header"
#define PANEL_TITLE     PREFIX "Title"
#define BTN_MINIMIZE    PREFIX "BtnMinimize"
#define LBL_INFO1       PREFIX "Info1"
#define LBL_INFO2       PREFIX "Info2"
#define BTN_MODE        PREFIX "BtnMode"

#define LBL_LOT         PREFIX "LblLot"
#define EDIT_LOT        PREFIX "EditLot"
#define CHK_SL          PREFIX "ChkSL"
#define LBL_SL          PREFIX "LblSL"
#define EDIT_SL         PREFIX "EditSL"
#define CHK_TP          PREFIX "ChkTP"
#define LBL_TP          PREFIX "LblTP"
#define EDIT_TP         PREFIX "EditTP"
#define CHK_BE          PREFIX "ChkBE"
#define LBL_BE          PREFIX "LblBE"
#define EDIT_BE         PREFIX "EditBE"
#define EDIT_BE_OFFSET  PREFIX "EditBEOffset"
#define CHK_TS          PREFIX "ChkTS"
#define LBL_TS          PREFIX "LblTS"
#define EDIT_TS         PREFIX "EditTS"
#define EDIT_TS_STEP    PREFIX "EditTSStep"

#define CHK_HEDGE       PREFIX "ChkHedge"
#define LBL_HEDGE       PREFIX "LblHedge"
#define EDIT_HEDGE      PREFIX "EditHedge"
#define BTN_ADD_TRENDLINE PREFIX "BtnAddTrendline"
#define BTN_CLEAR_TRENDLINES PREFIX "BtnClearTrendlines"
#define TL_PREVIEW_LINE PREFIX "TLPreview"

#define BTN_BUY         PREFIX "BtnBuy"
#define BTN_SELL        PREFIX "BtnSell"
#define BTN_BUY_PENDING PREFIX "BtnBuyPending"
#define BTN_SELL_PENDING PREFIX "BtnSellPending"
#define BTN_CLOSE_BUY   PREFIX "BtnCloseBuy"
#define BTN_CLOSE_SELL  PREFIX "BtnCloseSell"
#define BTN_CLOSE_HALF  PREFIX "BtnCloseHalf"
#define BTN_MANUAL_BE   PREFIX "BtnManualBE"
#define LBL_BE_TS_STATUS PREFIX "LblBeTsStatus"
#define BTN_TOGGLE_BE_TS PREFIX "BtnToggleBeTs"
#define BTN_CLOSE       PREFIX "BtnClose"
#define BTN_TL_TOGGLE   PREFIX "BtnTLToggle"

// ردیف تشخیص روند چندتایم‌فریمی، دقیقا زیر دکمه CLOSE ALL
#define LBL_TREND_M5    PREFIX "TrendM5"
#define LBL_TREND_M15   PREFIX "TrendM15"
#define LBL_TREND_M30   PREFIX "TrendM30"
#define LBL_TREND_H1    PREFIX "TrendH1"

#define PENDING_LINE    PREFIX "PendingLine"
#define BTN_PENDING_YES PREFIX "PendingBtnYes"
#define BTN_PENDING_NO  PREFIX "PendingBtnNo"

enum ENUM_PENDING_STATE { PENDING_NONE, PENDING_BUY, PENDING_SELL };
ENUM_PENDING_STATE g_pendingState = PENDING_NONE;

//--- ردیف تشخیص روند چندتایم‌فریمی (M5/M15/M30/H1) - ثابت، مستقل از تایم‌فریم فعلی چارت
#define TREND_ROW_COUNT 4
const ENUM_TIMEFRAMES g_trendTFs[TREND_ROW_COUNT]     = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1};
const string          g_trendTFLabels[TREND_ROW_COUNT] = {"M5", "M15", "M30", "H1"};
const string          g_trendLblNames[TREND_ROW_COUNT] = {LBL_TREND_M5, LBL_TREND_M15, LBL_TREND_M30, LBL_TREND_H1};
int   g_hTrendEMAFast[TREND_ROW_COUNT];
int   g_hTrendEMASlow[TREND_ROW_COUNT];
int   g_hTrendADX[TREND_ROW_COUNT];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   
   string symbol = _Symbol;
   g_gvLotKey       = PREFIX + symbol + "_Lot";
   g_gvSLKey        = PREFIX + symbol + "_SL";
   g_gvTPKey        = PREFIX + symbol + "_TP";
   g_gvBEKey        = PREFIX + symbol + "_BE";
   g_gvBEOffsetKey  = PREFIX + symbol + "_BEOffset";
   g_gvTSKey        = PREFIX + symbol + "_TS";
   g_gvTSStepKey    = PREFIX + symbol + "_TSStep";
   g_gvUseSLKey     = PREFIX + symbol + "_UseSL";
   g_gvUseTPKey     = PREFIX + symbol + "_UseTP";
   g_gvUseBEKey     = PREFIX + symbol + "_UseBE";
   g_gvUseTSKey     = PREFIX + symbol + "_UseTS";
   g_gvXKey         = PREFIX + symbol + "_X";
   g_gvYKey         = PREFIX + symbol + "_Y";
   g_gvTLStateKey   = PREFIX + symbol + "_TLState";
   g_gvMinKey       = PREFIX + symbol + "_Minimized";
   g_gvModeKey      = PREFIX + symbol + "_Mode";
   g_gvUseHedgeKey  = PREFIX + symbol + "_UseHedge";
   g_gvHedgeLossKey = PREFIX + symbol + "_HedgeLoss";
   g_gvTLCounterKey = PREFIX + symbol + "_TLCounter";
   g_gvBeTsExclCountKey = PREFIX + symbol + "_BeTsExclCount";
   g_gvBeTsExclPrefix   = PREFIX + symbol + "_BeTsExcl_";

   LoadOrInitVariables();
   CreateTrendRowHandles();
   CreatePanel();
   UpdateLiveStats();
   UpdateTrendRow();

   // هج خودکار فقط روی حساب‌های Hedging واقعی معنا دارد؛ در حساب Netting پوزیشن مخالف باعث نتینگ می‌شود نه هج واقعی
   if(g_useHedge && (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Auto-Hedge is enabled but this account is NOT a Hedging-type account. The feature will stay inactive until used on a Hedging account.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveVariables();
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   RemovePendingLineUI();
   ReleaseTrendRowHandles();
   Comment("");
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateLiveStats();
   UpdateTrendRow();
   ManageBreakEvenAndTrailing();
   ManageAutoHedge();
   UpdatePendingButtonsPosition();
   CheckIfAllTrendlinesCleared();
   
   if(g_trendlineActive)
   {
      CheckTrendlineTouch();
   }
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BTN_MINIMIZE)
      {
         g_isDragging = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         g_isMinimized = !g_isMinimized;
         ApplyMinimizeState();
         SaveVariables();
         ObjectSetInteger(0, BTN_MINIMIZE, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_MODE)
      {
         if(g_calcMode == MODE_POINTS) g_calcMode = MODE_USD;
         else if(g_calcMode == MODE_USD) g_calcMode = MODE_PERCENT;
         else g_calcMode = MODE_POINTS;
         UpdateModeButtonAppearance();
         SaveVariables();
         ObjectSetInteger(0, BTN_MODE, OBJPROP_STATE, false);
      }
      else if(sparam == CHK_SL)
      {
         g_useSL = !g_useSL;
         UpdateCheckboxAppearance(CHK_SL, g_useSL);
         SaveVariables();
         ObjectSetInteger(0, CHK_SL, OBJPROP_STATE, false);
      }
      else if(sparam == CHK_TP)
      {
         g_useTP = !g_useTP;
         UpdateCheckboxAppearance(CHK_TP, g_useTP);
         SaveVariables();
         ObjectSetInteger(0, CHK_TP, OBJPROP_STATE, false);
      }
      else if(sparam == CHK_BE)
      {
         g_useBE = !g_useBE;
         UpdateCheckboxAppearance(CHK_BE, g_useBE);
         SaveVariables();
         ObjectSetInteger(0, CHK_BE, OBJPROP_STATE, false);
      }
      else if(sparam == CHK_TS)
      {
         g_useTS = !g_useTS;
         UpdateCheckboxAppearance(CHK_TS, g_useTS);
         SaveVariables();
         ObjectSetInteger(0, CHK_TS, OBJPROP_STATE, false);
      }
      else if(sparam == CHK_HEDGE)
      {
         g_useHedge = !g_useHedge;
         UpdateCheckboxAppearance(CHK_HEDGE, g_useHedge);
         SaveVariables();
         ObjectSetInteger(0, CHK_HEDGE, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_ADD_TRENDLINE)
      {
         // به‌جای ساخت خودکار خط، وارد حالت رسم دستی دو-کلیکی می‌شویم؛ خطی ساخته نمی‌شود تا کاربر خودش کلیک کند
         RemoveTrendlinePreview();
         g_tlDrawStage = 1;
         Comment("EA Trendline: روی نقطه شروع خط کلیک کنید...");
         ObjectSetInteger(0, BTN_ADD_TRENDLINE, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_CLEAR_TRENDLINES)
      {
         ClearAllEATrendlines();
         ObjectSetInteger(0, BTN_CLEAR_TRENDLINES, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_BUY)
      {
         ExecuteTrade(ORDER_TYPE_BUY);
         ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_SELL)
      {
         ExecuteTrade(ORDER_TYPE_SELL);
         ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_BUY_PENDING)
      {
         CreatePendingLineUI(PENDING_BUY);
         ObjectSetInteger(0, BTN_BUY_PENDING, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_SELL_PENDING)
      {
         CreatePendingLineUI(PENDING_SELL);
         ObjectSetInteger(0, BTN_SELL_PENDING, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_PENDING_YES)
      {
         ConfirmPendingOrder();
         ObjectSetInteger(0, BTN_PENDING_YES, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_PENDING_NO)
      {
         RemovePendingLineUI();
         ObjectSetInteger(0, BTN_PENDING_NO, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_CLOSE_BUY)
      {
         ClosePositionsByType(POSITION_TYPE_BUY);
         ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_CLOSE_SELL)
      {
         ClosePositionsByType(POSITION_TYPE_SELL);
         ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_CLOSE_HALF)
      {
         CloseHalfPositions();
         ApplyManualBreakEven(); // Requirement 4: Break-Even with Close 50%
         ObjectSetInteger(0, BTN_CLOSE_HALF, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_MANUAL_BE)
      {
         ApplyManualBreakEven(); // Requirement 3: Manual BE
         ObjectSetInteger(0, BTN_MANUAL_BE, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_TOGGLE_BE_TS)
      {
         ToggleTicketBeTsExclusion(g_selectedPositionTicket); // اگر تیکتی انتخاب نشده باشد (0)، تابع بدون اثر برمی‌گردد
         UpdateBeTsStatusLabel();
         ObjectSetInteger(0, BTN_TOGGLE_BE_TS, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_CLOSE)
      {
         CloseAllPositions();
         ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
      }
      else if(sparam == BTN_TL_TOGGLE)
      {
         g_trendlineActive = !g_trendlineActive;
         UpdateTLButtonAppearance();
         SaveVariables();
         ObjectSetInteger(0, BTN_TL_TOGGLE, OBJPROP_STATE, false);
      }
      ChartRedraw();
   }
   
   // Requirement: کلیک روی چارت برای مشخص کردن دستی نقطه شروع و پایان خط جدید
   if(id == CHARTEVENT_CLICK)
   {
      if(g_tlDrawStage == 1 || g_tlDrawStage == 2)
      {
         int clickX = (int)lparam;
         int clickY = (int)dparam;
         bool insidePanel = IsPointInRect(clickX, clickY, g_panelX, g_panelY, PANEL_WIDTH, PANEL_HEIGHT);
         
         if(!insidePanel) // کلیک روی خود پنل نباید به‌عنوان نقطه خط در نظر گرفته شود
         {
            datetime clickTime;
            double   clickPrice;
            int      subWindow;
            if(ChartXYToTimePrice(0, clickX, clickY, subWindow, clickTime, clickPrice))
            {
               // Requirement 2: نقطه کلیک‌شده به نزدیک‌ترین بدنه/سایه کندل می‌چسبد (مگنت)
               datetime snapTime;
               double   snapPrice;
               if(SnapToCandle(clickTime, clickPrice, snapTime, snapPrice))
               {
                  clickTime  = snapTime;
                  clickPrice = snapPrice;
               }

               if(g_tlDrawStage == 1)
               {
                  g_tlDrawT1 = clickTime;
                  g_tlDrawP1 = clickPrice;
                  g_tlDrawStage = 2;
                  Comment("EA Trendline: حالا روی نقطه پایان خط کلیک کنید...");
                  CreateTrendlinePreview(g_tlDrawT1, g_tlDrawP1); // Requirement 1: از همین‌جا خط پیش‌نمایش نمایان می‌شود
               }
               else // g_tlDrawStage == 2
               {
                  CreateNewTrendline(g_tlDrawT1, g_tlDrawP1, clickTime, clickPrice);
                  g_tlDrawStage = 0;
                  Comment("");
                  RemoveTrendlinePreview();
               }
            }
         }
      }
      else // g_tlDrawStage == 0: کلیک روی چارت برای انتخاب پوزیشن جهت روشن/خاموش کردن BE/Trailing
      {
         int clickX = (int)lparam;
         int clickY = (int)dparam;
         bool insidePanel = IsPointInRect(clickX, clickY, g_panelX, g_panelY, PANEL_WIDTH, PANEL_HEIGHT);
         if(!insidePanel)
            TrySelectPositionAtClick(clickX, clickY);
      }
   }
   
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == EDIT_LOT)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT));
         if(val > 0) g_panelLot = val;
         else ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_panelLot, 2));
      }
      else if(sparam == EDIT_SL)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_SL, OBJPROP_TEXT));
         if(val >= 0) g_panelSL = val;
         else ObjectSetString(0, EDIT_SL, OBJPROP_TEXT, DoubleToString(g_panelSL, 1));
      }
      else if(sparam == EDIT_TP)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_TP, OBJPROP_TEXT));
         if(val >= 0) g_panelTP = val;
         else ObjectSetString(0, EDIT_TP, OBJPROP_TEXT, DoubleToString(g_panelTP, 1));
      }
      else if(sparam == EDIT_BE)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_BE, OBJPROP_TEXT));
         if(val >= 0) g_panelBE = val;
         else ObjectSetString(0, EDIT_BE, OBJPROP_TEXT, DoubleToString(g_panelBE, 1));
      }
      else if(sparam == EDIT_BE_OFFSET)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_BE_OFFSET, OBJPROP_TEXT));
         if(val >= 0) g_panelBEOffset = val;
         else ObjectSetString(0, EDIT_BE_OFFSET, OBJPROP_TEXT, DoubleToString(g_panelBEOffset, 1));
      }
      else if(sparam == EDIT_TS)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_TS, OBJPROP_TEXT));
         if(val >= 0) g_panelTS = val;
         else ObjectSetString(0, EDIT_TS, OBJPROP_TEXT, DoubleToString(g_panelTS, 1));
      }
      else if(sparam == EDIT_TS_STEP)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_TS_STEP, OBJPROP_TEXT));
         if(val >= 0) g_panelTSStep = val;
         else ObjectSetString(0, EDIT_TS_STEP, OBJPROP_TEXT, DoubleToString(g_panelTSStep, 1));
      }
      else if(sparam == EDIT_HEDGE)
      {
         double val = StringToDouble(ObjectGetString(0, EDIT_HEDGE, OBJPROP_TEXT));
         if(val >= 0) g_panelHedgeLoss = val;
         else ObjectSetString(0, EDIT_HEDGE, OBJPROP_TEXT, DoubleToString(g_panelHedgeLoss, 1));
      }
      SaveVariables();
   }
   
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseState = (uint)StringToInteger(sparam);
      
      bool isLeftClick = ((mouseState & 1) == 1);
      bool inHeader = IsPointInRect(mouseX, mouseY, g_panelX, g_panelY, PANEL_WIDTH, HEADER_HEIGHT);
      bool onMinimizeButton = IsPointInRect(mouseX, mouseY, g_panelX + 202, g_panelY + 3, 22, 19);
      
      if(isLeftClick)
      {
         if(!g_isDragging)
         {
            if(inHeader && !onMinimizeButton)
            {
               g_isDragging = true;
               g_dragOffsetX = mouseX - g_panelX;
               g_dragOffsetY = mouseY - g_panelY;
               ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
            }
         }
         else
         {
            g_panelX = mouseX - g_dragOffsetX;
            g_panelY = mouseY - g_dragOffsetY;
            if(g_panelX < 0) g_panelX = 0;
            if(g_panelY < 0) g_panelY = 0;
            MovePanel(g_panelX, g_panelY);
            SaveVariables();
         }
      }
      else
      {
         if(g_isDragging) ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         g_isDragging = false;
      }
      
      if(g_pendingState != PENDING_NONE)
      {
         UpdatePendingButtonsPosition();
      }
      
      // Requirement 1 & 2: خط پیش‌نمایش همراه حرکت ماوس تا نقطه دوم، با چسبیدن مگنتی به کندل زیر مکان‌نما
      if(g_tlDrawStage == 2)
      {
         datetime hoverTime;
         double   hoverPrice;
         int      subWindow;
         if(ChartXYToTimePrice(0, mouseX, mouseY, subWindow, hoverTime, hoverPrice))
         {
            datetime snapTime;
            double   snapPrice;
            if(SnapToCandle(hoverTime, hoverPrice, snapTime, snapPrice))
               UpdateTrendlinePreview(snapTime, snapPrice);
            else
               UpdateTrendlinePreview(hoverTime, hoverPrice);
            ChartRedraw();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Variables Management                                             |
//+------------------------------------------------------------------+
void LoadOrInitVariables()
{
   if(GlobalVariableCheck(g_gvLotKey)) g_panelLot = GlobalVariableGet(g_gvLotKey); else g_panelLot = InpLotSize;
   if(GlobalVariableCheck(g_gvSLKey))  g_panelSL = GlobalVariableGet(g_gvSLKey); else g_panelSL = InpStopLoss;
   if(GlobalVariableCheck(g_gvTPKey))  g_panelTP = GlobalVariableGet(g_gvTPKey); else g_panelTP = InpTakeProfit;
   if(GlobalVariableCheck(g_gvBEKey))  g_panelBE = GlobalVariableGet(g_gvBEKey); else g_panelBE = InpBreakEvenTrigger;
   if(GlobalVariableCheck(g_gvBEOffsetKey))  g_panelBEOffset = GlobalVariableGet(g_gvBEOffsetKey); else g_panelBEOffset = InpBreakEvenOffset;
   if(GlobalVariableCheck(g_gvTSKey))  g_panelTS = GlobalVariableGet(g_gvTSKey); else g_panelTS = InpTrailingStop;
   if(GlobalVariableCheck(g_gvTSStepKey))  g_panelTSStep = GlobalVariableGet(g_gvTSStepKey); else g_panelTSStep = InpTrailingStep;

   if(GlobalVariableCheck(g_gvUseSLKey)) g_useSL = (GlobalVariableGet(g_gvUseSLKey) > 0); else g_useSL = InpUseSL;
   if(GlobalVariableCheck(g_gvUseTPKey)) g_useTP = (GlobalVariableGet(g_gvUseTPKey) > 0); else g_useTP = InpUseTP;
   if(GlobalVariableCheck(g_gvUseBEKey)) g_useBE = (GlobalVariableGet(g_gvUseBEKey) > 0); else g_useBE = InpUseBreakEven;
   if(GlobalVariableCheck(g_gvUseTSKey)) g_useTS = (GlobalVariableGet(g_gvUseTSKey) > 0); else g_useTS = InpUseTrailingStop;
      
   if(GlobalVariableCheck(g_gvXKey))   g_panelX = (int)GlobalVariableGet(g_gvXKey);
   if(GlobalVariableCheck(g_gvYKey))   g_panelY = (int)GlobalVariableGet(g_gvYKey);
   if(GlobalVariableCheck(g_gvTLStateKey)) g_trendlineActive = (GlobalVariableGet(g_gvTLStateKey) > 0); else g_trendlineActive = InpInitialTLState;
   if(GlobalVariableCheck(g_gvMinKey)) g_isMinimized = (GlobalVariableGet(g_gvMinKey) > 0);
   if(GlobalVariableCheck(g_gvModeKey)) g_calcMode = (ENUM_CALC_MODE)GlobalVariableGet(g_gvModeKey);

   if(GlobalVariableCheck(g_gvUseHedgeKey)) g_useHedge = (GlobalVariableGet(g_gvUseHedgeKey) > 0); else g_useHedge = InpUseAutoHedge;
   if(GlobalVariableCheck(g_gvHedgeLossKey)) g_panelHedgeLoss = GlobalVariableGet(g_gvHedgeLossKey); else g_panelHedgeLoss = InpAutoHedgeLossUSD;
   if(GlobalVariableCheck(g_gvTLCounterKey)) g_trendlineCounter = (int)GlobalVariableGet(g_gvTLCounterKey); else g_trendlineCounter = 0;

   // بازیابی لیست پوزیشن‌هایی که کاربر دستی BE/Trailing را برایشان خاموش کرده بود (ماندگار بین ری‌استارت EA/ترمینال)
   ArrayFree(g_beTsExcludedTickets);
   if(GlobalVariableCheck(g_gvBeTsExclCountKey))
   {
      int savedCount = (int)GlobalVariableGet(g_gvBeTsExclCountKey);
      for(int i = 0; i < savedCount; i++)
      {
         string key = g_gvBeTsExclPrefix + IntegerToString(i);
         if(GlobalVariableCheck(key))
         {
            ulong t = (ulong)GlobalVariableGet(key);
            if(t != 0)
            {
               int n = ArraySize(g_beTsExcludedTickets);
               ArrayResize(g_beTsExcludedTickets, n + 1);
               g_beTsExcludedTickets[n] = t;
            }
         }
      }
   }
}

void SaveVariables()
{
   GlobalVariableSet(g_gvLotKey, g_panelLot);
   GlobalVariableSet(g_gvSLKey, g_panelSL);
   GlobalVariableSet(g_gvTPKey, g_panelTP);
   GlobalVariableSet(g_gvBEKey, g_panelBE);
   GlobalVariableSet(g_gvBEOffsetKey, g_panelBEOffset);
   GlobalVariableSet(g_gvTSKey, g_panelTS);
   GlobalVariableSet(g_gvTSStepKey, g_panelTSStep);
   GlobalVariableSet(g_gvUseSLKey, g_useSL ? 1.0 : 0.0);
   GlobalVariableSet(g_gvUseTPKey, g_useTP ? 1.0 : 0.0);
   GlobalVariableSet(g_gvUseBEKey, g_useBE ? 1.0 : 0.0);
   GlobalVariableSet(g_gvUseTSKey, g_useTS ? 1.0 : 0.0);
   GlobalVariableSet(g_gvXKey, (double)g_panelX);
   GlobalVariableSet(g_gvYKey, (double)g_panelY);
   GlobalVariableSet(g_gvTLStateKey, g_trendlineActive ? 1.0 : 0.0);
   GlobalVariableSet(g_gvMinKey, g_isMinimized ? 1.0 : 0.0);
   GlobalVariableSet(g_gvModeKey, (double)g_calcMode);
   GlobalVariableSet(g_gvUseHedgeKey, g_useHedge ? 1.0 : 0.0);
   GlobalVariableSet(g_gvHedgeLossKey, g_panelHedgeLoss);
   GlobalVariableSet(g_gvTLCounterKey, (double)g_trendlineCounter);
}

//+------------------------------------------------------------------+
//| GUI Creation & Manipulation                                      |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int w = PANEL_WIDTH;
   int h = PANEL_HEIGHT; // ارتفاع پنل شامل ردیف Hedge، دکمه رسم خط جدید و دکمه پاک‌کردن همه خطوط
   
   CreateRectLabel(PANEL_BG, g_panelX, g_panelY, w, h, C'35,35,35', C'70,70,70');
   ObjectSetInteger(0, PANEL_BG, OBJPROP_ZORDER, 0);

   CreateRectLabel(PANEL_HEADER, g_panelX, g_panelY, w, HEADER_HEIGHT, C'50,50,50', C'90,90,90');
   ObjectSetInteger(0, PANEL_HEADER, OBJPROP_ZORDER, 1);
   
   CreateLabel(PANEL_TITLE, "ADVANCED PANEL v" + EA_VERSION, g_panelX + 10, g_panelY + 5, clrGold, 9, true);
   ObjectSetInteger(0, PANEL_TITLE, OBJPROP_ZORDER, 2);
   
   CreateButton(BTN_MINIMIZE, g_isMinimized ? "+" : "_", g_panelX + 202, g_panelY + 3, 22, 19, C'80,80,80', clrWhite);
   ObjectSetInteger(0, BTN_MINIMIZE, OBJPROP_ZORDER, 100);

   CreateLabel(LBL_INFO1, "Bal: -- | Eq: --", g_panelX + 10, g_panelY + 33, clrWhite, 8, false);
   CreateLabel(LBL_INFO2, "Profit: -- | Pos: 0", g_panelX + 10, g_panelY + 48, clrWhite, 8, false);
   CreateRectLabel(PREFIX + "Line", g_panelX + 10, g_panelY + 65, w - 20, 1, C'80,80,80', C'80,80,80');

   CreateButton(BTN_MODE, "", g_panelX + 12, g_panelY + 75, 203, 22, C'60,80,120', clrWhite);
   UpdateModeButtonAppearance();

   CreateLabel(LBL_LOT, "Lot Size:", g_panelX + 40, g_panelY + 104, clrWhite, 8, true);
   CreateEdit(EDIT_LOT, DoubleToString(g_panelLot, 2), g_panelX + 130, g_panelY + 100, 85, 16);

   CreateButton(CHK_SL, "", g_panelX + 12, g_panelY + 130, 22, 16, C'60,60,60', clrWhite);
   UpdateCheckboxAppearance(CHK_SL, g_useSL);
   CreateLabel(LBL_SL, "StopLoss", g_panelX + 40, g_panelY + 134, clrWhite, 8, true);
   CreateEdit(EDIT_SL, DoubleToString(g_panelSL, 1), g_panelX + 130, g_panelY + 130, 85, 16);

   CreateButton(CHK_TP, "", g_panelX + 12, g_panelY + 160, 22, 16, C'60,60,60', clrWhite);
   UpdateCheckboxAppearance(CHK_TP, g_useTP);
   CreateLabel(LBL_TP, "TakeProfit", g_panelX + 40, g_panelY + 164, clrWhite, 8, true);
   CreateEdit(EDIT_TP, DoubleToString(g_panelTP, 1), g_panelX + 130, g_panelY + 160, 85, 16);

   CreateButton(CHK_BE, "", g_panelX + 12, g_panelY + 190, 22, 16, C'60,60,60', clrWhite);
   UpdateCheckboxAppearance(CHK_BE, g_useBE);
   CreateLabel(LBL_BE, "BE / Offset", g_panelX + 40, g_panelY + 194, clrWhite, 8, true);
   CreateEdit(EDIT_BE, DoubleToString(g_panelBE, 1), g_panelX + 130, g_panelY + 190, 40, 16);
   CreateEdit(EDIT_BE_OFFSET, DoubleToString(g_panelBEOffset, 1), g_panelX + 175, g_panelY + 190, 40, 16);

   CreateButton(CHK_TS, "", g_panelX + 12, g_panelY + 220, 22, 16, C'60,60,60', clrWhite);
   UpdateCheckboxAppearance(CHK_TS, g_useTS);
   CreateLabel(LBL_TS, "TS / Step", g_panelX + 40, g_panelY + 224, clrWhite, 8, true);
   CreateEdit(EDIT_TS, DoubleToString(g_panelTS, 1), g_panelX + 130, g_panelY + 220, 40, 16);
   CreateEdit(EDIT_TS_STEP, DoubleToString(g_panelTSStep, 1), g_panelX + 175, g_panelY + 220, 40, 16);

   CreateButton(CHK_HEDGE, "", g_panelX + 12, g_panelY + 250, 22, 16, C'60,60,60', clrWhite);
   UpdateCheckboxAppearance(CHK_HEDGE, g_useHedge);
   CreateLabel(LBL_HEDGE, "Hedge Loss", g_panelX + 40, g_panelY + 254, clrWhite, 8, true);
   CreateEdit(EDIT_HEDGE, DoubleToString(g_panelHedgeLoss, 1), g_panelX + 130, g_panelY + 250, 85, 16);

   CreateButton(BTN_TL_TOGGLE, "", g_panelX + 12, g_panelY + 280, 203, 24, C'70,70,70', clrWhite);
   UpdateTLButtonAppearance();

   CreateButton(BTN_ADD_TRENDLINE, "+ NEW TREND LINE (" + InpAutoTrendlinePrefix + ")", g_panelX + 12, g_panelY + 310, 203, 24, C'40,80,130', clrWhite);

   CreateButton(BTN_CLEAR_TRENDLINES, "CLEAR ALL TREND LINES", g_panelX + 12, g_panelY + 340, 203, 24, C'110,40,40', clrWhite);

   CreateButton(BTN_BUY, "BUY", g_panelX + 12, g_panelY + 372, 98, 26, C'0,130,0', clrWhite);
   CreateButton(BTN_SELL, "SELL", g_panelX + 117, g_panelY + 372, 98, 26, C'170,0,0', clrWhite);

   CreateButton(BTN_BUY_PENDING, "BUY PENDING", g_panelX + 12, g_panelY + 402, 98, 24, C'0,90,0', clrWhite);
   CreateButton(BTN_SELL_PENDING, "SELL PENDING", g_panelX + 117, g_panelY + 402, 98, 24, C'130,0,0', clrWhite);

   CreateButton(BTN_CLOSE_BUY, "CLOSE BUYS", g_panelX + 12, g_panelY + 432, 98, 24, C'180,90,0', clrWhite);
   CreateButton(BTN_CLOSE_SELL, "CLOSE SELLS", g_panelX + 117, g_panelY + 432, 98, 24, C'180,90,0', clrWhite);

   CreateButton(BTN_CLOSE_HALF, "CLOSE 50%", g_panelX + 12, g_panelY + 462, 98, 24, C'100,100,0', clrWhite);
   CreateButton(BTN_MANUAL_BE, "MANUAL BE", g_panelX + 117, g_panelY + 462, 98, 24, C'40,100,150', clrWhite);
   
   CreateButton(BTN_CLOSE, "CLOSE ALL", g_panelX + 12, g_panelY + 492, 203, 26, C'70,70,70', clrWhite);

   // ردیف تشخیص روند M5 / M15 / M30 / H1 - دقیقا زیر دکمه CLOSE ALL (Close All bottom edge = panelY + 518)
   int trendRowY = g_panelY + 526;
   int trendColX[TREND_ROW_COUNT] = {g_panelX + 15, g_panelX + 68, g_panelX + 121, g_panelX + 174};
   for(int i = 0; i < TREND_ROW_COUNT; i++)
      CreateLabel(g_trendLblNames[i], g_trendTFLabels[i] + " …", trendColX[i], trendRowY, clrSilver, 9, true);

   // ردیف انتخاب دستی پوزیشن برای فعال/غیرفعال کردن BE و Trailing Stop به‌صورت جداگانه برای هر پوزیشن:
   // روی خط پوزیشن مورد نظر روی چارت کلیک کنید تا انتخاب شود، سپس این دکمه را بزنید تا وضعیتش تغییر کند
   CreateLabel(LBL_BE_TS_STATUS, "پوزیشنی انتخاب نشده", g_panelX + 12, g_panelY + 550, clrSilver, 8, false);
   CreateButton(BTN_TOGGLE_BE_TS, "TOGGLE BE/TS FOR SELECTED", g_panelX + 12, g_panelY + 566, 203, 22, C'70,70,70', clrWhite);

   ApplyMinimizeState();
   UpdateLabelsMode();
   UpdateTrendRow();
   ChartRedraw();
}

void UpdateCheckboxAppearance(string chkName, bool state)
{
   ObjectSetString(0, chkName, OBJPROP_TEXT, state ? "✓" : "—");
   ObjectSetInteger(0, chkName, OBJPROP_BGCOLOR, state ? C'0,120,60' : C'80,80,80');
   ObjectSetInteger(0, chkName, OBJPROP_COLOR, state ? clrWhite : C'150,150,150');
}

void UpdateModeButtonAppearance()
{
   string modeText = "Mode: POINTS";
   if(g_calcMode == MODE_USD) modeText = "Mode: USD ($)";
   else if(g_calcMode == MODE_PERCENT) modeText = "Mode: PERCENT (%)";
   
   ObjectSetString(0, BTN_MODE, OBJPROP_TEXT, modeText);
   UpdateLabelsMode();
}

void UpdateLabelsMode()
{
   string unit = (g_calcMode == MODE_USD) ? " ($)" : (g_calcMode == MODE_PERCENT) ? " (%)" : " (pt)";
   ObjectSetString(0, LBL_SL, OBJPROP_TEXT, "StopLoss" + unit);
   ObjectSetString(0, LBL_TP, OBJPROP_TEXT, "TakeProfit" + unit);
   ObjectSetString(0, LBL_BE, OBJPROP_TEXT, "BE / Offset" + unit);
   ObjectSetString(0, LBL_TS, OBJPROP_TEXT, "TS / Step" + unit);
   ObjectSetString(0, LBL_HEDGE, OBJPROP_TEXT, "Hedge Loss" + unit);
}

void RefreshMinimizeButton()
{
   if(ObjectFind(0, BTN_MINIMIZE) >= 0)
      ObjectDelete(0, BTN_MINIMIZE);

   CreateButton(BTN_MINIMIZE, g_isMinimized ? "+" : "_", g_panelX + 202, g_panelY + 3, 22, 19, C'80,80,80', clrWhite);
   ObjectSetInteger(0, BTN_MINIMIZE, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, BTN_MINIMIZE, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, BTN_MINIMIZE, OBJPROP_STATE, false);
}

void RefreshPanelTitle()
{
   if(ObjectFind(0, PANEL_TITLE) >= 0)
      ObjectDelete(0, PANEL_TITLE);

   CreateLabel(PANEL_TITLE, "ADVANCED PANEL v" + EA_VERSION, g_panelX + 10, g_panelY + 5, clrGold, 9, true);
   ObjectSetInteger(0, PANEL_TITLE, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, PANEL_TITLE, OBJPROP_ZORDER, 2);
}

void ApplyMinimizeState()
{
   long visibility = g_isMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
   
   string childObjects[] = {
      PANEL_BG, LBL_INFO1, LBL_INFO2, PREFIX + "Line", BTN_MODE,
      LBL_LOT, EDIT_LOT, CHK_SL, LBL_SL, EDIT_SL, 
      CHK_TP, LBL_TP, EDIT_TP, CHK_BE, LBL_BE, EDIT_BE, EDIT_BE_OFFSET,
      CHK_TS, LBL_TS, EDIT_TS, EDIT_TS_STEP,
      CHK_HEDGE, LBL_HEDGE, EDIT_HEDGE,
      BTN_TL_TOGGLE, BTN_ADD_TRENDLINE, BTN_CLEAR_TRENDLINES, BTN_BUY, BTN_SELL, BTN_BUY_PENDING, BTN_SELL_PENDING,
      BTN_CLOSE_BUY, BTN_CLOSE_SELL, BTN_CLOSE_HALF, BTN_MANUAL_BE, BTN_CLOSE,
      LBL_TREND_M5, LBL_TREND_M15, LBL_TREND_M30, LBL_TREND_H1,
      LBL_BE_TS_STATUS, BTN_TOGGLE_BE_TS
   };
   
   for(int i = 0; i < ArraySize(childObjects); i++)
      ObjectSetInteger(0, childObjects[i], OBJPROP_TIMEFRAMES, visibility);
      
   ObjectSetInteger(0, PANEL_HEADER, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   
   ObjectSetInteger(0, PANEL_HEADER, OBJPROP_ZORDER, 1);
   RefreshPanelTitle();
   RefreshMinimizeButton();
   
   if(!g_isMinimized)
   {
      ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_panelLot, 2));
      ObjectSetString(0, EDIT_SL, OBJPROP_TEXT, DoubleToString(g_panelSL, 1));
      ObjectSetString(0, EDIT_TP, OBJPROP_TEXT, DoubleToString(g_panelTP, 1));
      ObjectSetString(0, EDIT_BE, OBJPROP_TEXT, DoubleToString(g_panelBE, 1));
      ObjectSetString(0, EDIT_BE_OFFSET, OBJPROP_TEXT, DoubleToString(g_panelBEOffset, 1));
      ObjectSetString(0, EDIT_TS, OBJPROP_TEXT, DoubleToString(g_panelTS, 1));
      ObjectSetString(0, EDIT_TS_STEP, OBJPROP_TEXT, DoubleToString(g_panelTSStep, 1));
      ObjectSetString(0, EDIT_HEDGE, OBJPROP_TEXT, DoubleToString(g_panelHedgeLoss, 1));
   }
   ChartRedraw();
}

// دکمه روشن/خاموش که اکنون بر روی همه خطوط ساخته‌شده توسط اکسپرت (خط ثابت + خطوط Ali_N) اعمال می‌شود
void UpdateTLButtonAppearance()
{
   ObjectSetString(0, BTN_TL_TOGGLE, OBJPROP_TEXT, "EA TREND LINES: " + (g_trendlineActive ? "ON" : "OFF"));
   ObjectSetInteger(0, BTN_TL_TOGGLE, OBJPROP_BGCOLOR, g_trendlineActive ? C'0,120,60' : C'120,40,40');
}

bool IsPointInRect(int px, int py, int x, int y, int w, int h)
{
   return (px >= x && px <= x + w && py >= y && py <= y + h);
}

void MovePanel(int x, int y)
{
   int dx = x - (int)ObjectGetInteger(0, PANEL_BG, OBJPROP_XDISTANCE);
   int dy = y - (int)ObjectGetInteger(0, PANEL_BG, OBJPROP_YDISTANCE);
   
   string objects[] = {
      PANEL_BG, PANEL_HEADER, PANEL_TITLE, BTN_MINIMIZE, LBL_INFO1, LBL_INFO2, PREFIX + "Line", BTN_MODE,
      LBL_LOT, EDIT_LOT, CHK_SL, LBL_SL, EDIT_SL, 
      CHK_TP, LBL_TP, EDIT_TP, CHK_BE, LBL_BE, EDIT_BE, EDIT_BE_OFFSET,
      CHK_TS, LBL_TS, EDIT_TS, EDIT_TS_STEP,
      CHK_HEDGE, LBL_HEDGE, EDIT_HEDGE,
      BTN_TL_TOGGLE, BTN_ADD_TRENDLINE, BTN_CLEAR_TRENDLINES, BTN_BUY, BTN_SELL, BTN_BUY_PENDING, BTN_SELL_PENDING,
      BTN_CLOSE_BUY, BTN_CLOSE_SELL, BTN_CLOSE_HALF, BTN_MANUAL_BE, BTN_CLOSE,
      LBL_TREND_M5, LBL_TREND_M15, LBL_TREND_M30, LBL_TREND_H1,
      LBL_BE_TS_STATUS, BTN_TOGGLE_BE_TS
   };
   
   for(int i = 0; i < ArraySize(objects); i++)
   {
      ObjectSetInteger(0, objects[i], OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, objects[i], OBJPROP_XDISTANCE) + dx);
      ObjectSetInteger(0, objects[i], OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, objects[i], OBJPROP_YDISTANCE) + dy);
   }
   ChartRedraw();
}

void CreateRectLabel(string name, int x, int y, int w, int h, color bgClr, color borderClr)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, (name == PANEL_HEADER));
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, bool fontBold)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   if(fontBold) ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

void CreateEdit(string name, string text, int x, int y, int w, int h)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'50,50,50');
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

void CreateButton(string name, string text, int x, int y, int w, int h, color bgClr, color textClr)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

//+------------------------------------------------------------------+
//| ردیف تشخیص روند M5/M15/M30/H1 (زیر دکمه CLOSE ALL)                |
//| منطق: جهت از EMA50 نسبت به EMA200 گرفته می‌شود و توسط ADX(14)     |
//| بزرگ‌تر از آستانه تایید می‌شود. NO-REPAINT: تمام مقادیر از کندل    |
//| بسته‌شده (shift 1) خوانده می‌شوند، هرگز از شیفت 0 (کندل جاری).      |
//+------------------------------------------------------------------+
void CreateTrendRowHandles()
{
   for(int i = 0; i < TREND_ROW_COUNT; i++)
   {
      g_hTrendEMAFast[i] = iMA(_Symbol, g_trendTFs[i], InpTrendEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_hTrendEMASlow[i] = iMA(_Symbol, g_trendTFs[i], InpTrendEMASlow, 0, MODE_EMA, PRICE_CLOSE);
      g_hTrendADX[i]     = iADX(_Symbol, g_trendTFs[i], InpTrendADXPeriod);

      if(g_hTrendEMAFast[i] == INVALID_HANDLE || g_hTrendEMASlow[i] == INVALID_HANDLE || g_hTrendADX[i] == INVALID_HANDLE)
         Print("WARNING: Trend row indicator handle failed for ", g_trendTFLabels[i], ", error code: ", GetLastError());
   }
}

void ReleaseTrendRowHandles()
{
   for(int i = 0; i < TREND_ROW_COUNT; i++)
   {
      if(g_hTrendEMAFast[i] != INVALID_HANDLE) IndicatorRelease(g_hTrendEMAFast[i]);
      if(g_hTrendEMASlow[i] != INVALID_HANDLE) IndicatorRelease(g_hTrendEMASlow[i]);
      if(g_hTrendADX[i]     != INVALID_HANDLE) IndicatorRelease(g_hTrendADX[i]);
   }
}

// جهت روند یک تایم‌فریم را محاسبه می‌کند. فقط از کندل بسته‌شده (index >= 1) می‌خواند تا هرگز ریپینت نشود.
// جهت همیشه فوری و مستقیم از کراس EMA50/EMA200 گرفته می‌شود (بدون تاخیر/نگه‌داشتن سیگنال قبلی - مناسب اسکالپ روی M1).
// ADX(14) فقط "قدرت" روند را مشخص می‌کند و روی شدت رنگ اثر می‌گذارد، نه روی خود جهت یا زمان به‌روزرسانی آن.
bool CalcTrendDirection(int idx, bool &bullishOut, bool &confirmedOut)
{
   if(g_hTrendEMAFast[idx] == INVALID_HANDLE || g_hTrendEMASlow[idx] == INVALID_HANDLE || g_hTrendADX[idx] == INVALID_HANDLE)
      return false;

   double emaFast[1], emaSlow[1], adxMain[1];

   // shift = 1  =>  همیشه از آخرین کندل بسته‌شده می‌خواند، هرگز از کندل در حال شکل‌گیری (shift 0). این نکته تضمین‌کننده عدم Repaint است.
   if(CopyBuffer(g_hTrendEMAFast[idx], 0, 1, 1, emaFast) <= 0) return false;
   if(CopyBuffer(g_hTrendEMASlow[idx], 0, 1, 1, emaSlow) <= 0) return false;
   if(CopyBuffer(g_hTrendADX[idx], 0, 1, 1, adxMain) <= 0) return false; // بافر 0 = ADX Main Line

   bullishOut   = (emaFast[0] > emaSlow[0]);        // EMA50 بالای EMA200 = صعودی، پایین = نزولی - همیشه به‌روز، بدون تاخیر
   confirmedOut = (adxMain[0] > InpTrendADXThreshold); // فقط برای تعیین شدت رنگ استفاده می‌شود، نه گیت کردن جهت
   return true;
}

void UpdateTrendRow()
{
   for(int i = 0; i < TREND_ROW_COUNT; i++)
   {
      bool bullish, confirmed;
      bool ok = CalcTrendDirection(i, bullish, confirmed);

      if(!ok)
      {
         // دیتای تاریخی هنوز کامل لود نشده؛ حالت انتظار نمایش داده می‌شود (نه صعودی و نه نزولی جعلی)
         ObjectSetString(0, g_trendLblNames[i], OBJPROP_TEXT, g_trendTFLabels[i] + " …");
         ObjectSetInteger(0, g_trendLblNames[i], OBJPROP_COLOR, clrSilver);
         continue;
      }

      string arrow = bullish ? "▲" : "▼";
      // رنگ پررنگ = ADX روند رو تایید کرده (قوی)، رنگ کم‌رنگ = جهت درسته ولی روند هنوز ضعیفه
      color  clr;
      if(bullish) clr = confirmed ? clrLime : (color)C'70,140,70';
      else        clr = confirmed ? clrRed  : (color)C'150,70,70';

      ObjectSetString(0, g_trendLblNames[i], OBJPROP_TEXT, g_trendTFLabels[i] + " " + arrow);
      ObjectSetInteger(0, g_trendLblNames[i], OBJPROP_COLOR, clr);
   }
}

//+------------------------------------------------------------------+
//| Stats & Conversion Functions                                     |
//+------------------------------------------------------------------+
void UpdateLiveStats()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit  = AccountInfoDouble(ACCOUNT_PROFIT);
   int posCount = GetTotalOpenPositionsCount();
   
   ObjectSetString(0, LBL_INFO1, OBJPROP_TEXT, StringFormat("Bal: %.2f | Eq: %.2f", balance, equity));
   ObjectSetString(0, LBL_INFO2, OBJPROP_TEXT, StringFormat("Profit: %.2f | Open Pos: %d", profit, posCount));
   ObjectSetInteger(0, LBL_INFO2, OBJPROP_COLOR, profit >= 0 ? clrLime : clrRed);
}

int GetTotalOpenPositionsCount()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) count++;
   return count;
}

void ConvertValueToPoints(double valInput, double lot, double &outPoints)
{
   if(g_calcMode == MODE_POINTS)
   {
      outPoints = valInput; return;
   }
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue <= 0 || point <= 0 || lot <= 0)
   {
      outPoints = valInput; return;
   }
   
   double valuePerPoint = tickValue * (point / tickSize) * lot;
   
   if(g_calcMode == MODE_USD)
   {
      outPoints = (valInput > 0) ? (valInput / valuePerPoint) : 0;
   }
   else if(g_calcMode == MODE_PERCENT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double targetAmount = balance * (valInput / 100.0);
      outPoints = (targetAmount > 0) ? (targetAmount / valuePerPoint) : 0;
   }
}

double CalculateLotSize(double tempSLPoints)
{
   if(InpLotType == LOT_TYPE_FIXED || tempSLPoints <= 0) return g_panelLot;
      
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue <= 0 || point <= 0) return g_panelLot;
   double valuePerPoint = tickValue * (point / tickSize);
   
   double calculatedLot = riskAmount / (tempSLPoints * valuePerPoint);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   calculatedLot = MathFloor(calculatedLot / stepLot) * stepLot;
   if(calculatedLot < minLot) calculatedLot = minLot;
   if(calculatedLot > maxLot) calculatedLot = maxLot;
   return calculatedLot;
}

//+------------------------------------------------------------------+
//| Trade Execution & Management                                     |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE posType)
{
   if(!InpPreventMulti) return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType) return true;
      }
   }
   return false;
}

void AdjustExactSLTP(ulong orderTicket, ENUM_ORDER_TYPE orderType)
{
   if(!PositionSelectByTicket(orderTicket) && !PositionSelect(_Symbol)) return;
   
   double exactOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double lot = PositionGetDouble(POSITION_VOLUME);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPoints = 0, tpPoints = 0;
   if(g_useSL && g_panelSL > 0) ConvertValueToPoints(g_panelSL, lot, slPoints);
   if(g_useTP && g_panelTP > 0) ConvertValueToPoints(g_panelTP, lot, tpPoints);
   
   double slPrice = 0, tpPrice = 0;
   if(orderType == ORDER_TYPE_BUY)
   {
      if(slPoints > 0) slPrice = exactOpenPrice - (slPoints * point);
      if(tpPoints > 0) tpPrice = exactOpenPrice + (tpPoints * point);
   }
   else
   {
      if(slPoints > 0) slPrice = exactOpenPrice + (slPoints * point);
      if(tpPoints > 0) tpPrice = exactOpenPrice - (tpPoints * point);
   }
   
   if(slPrice > 0 || tpPrice > 0)
   {
      trade.PositionModify(PositionGetInteger(POSITION_TICKET), slPrice, tpPrice);
   }
}

bool ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   // اجازه باز کردن پوزیشن دستی چه در جهت موافق و چه مخالف پوزیشن باز فعلی داده می‌شود (بدون محدودیت)
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = g_panelLot;
   
   if(InpLotType == LOT_TYPE_RISK && g_useSL && g_panelSL > 0)
   {
      double tempSLPoints = g_panelSL;
      if (g_calcMode == MODE_USD || g_calcMode == MODE_PERCENT) 
      {
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double valPerPt1Lot = tickValue * (point / tickSize);
         if(g_calcMode == MODE_USD) tempSLPoints = g_panelSL / valPerPt1Lot;
         if(g_calcMode == MODE_PERCENT) tempSLPoints = (AccountInfoDouble(ACCOUNT_BALANCE) * (g_panelSL/100.0)) / valPerPt1Lot;
      }
      lot = CalculateLotSize(tempSLPoints);
   }
   
   // Requirement 1: Send without SL/TP, capture exact PriceOpen, then adjust.
   bool result = false;
   if(orderType == ORDER_TYPE_BUY) result = trade.Buy(lot, _Symbol, price, 0, 0, "Panel Buy");
   else if(orderType == ORDER_TYPE_SELL) result = trade.Sell(lot, _Symbol, price, 0, 0, "Panel Sell");
   
   if(result)
   {
      ulong orderTicket = trade.ResultOrder();
      Sleep(200); // Allow server registration
      AdjustExactSLTP(orderTicket, orderType);
   }
   return result;
}

void ApplyManualBreakEven()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double posVolume = PositionGetDouble(POSITION_VOLUME);
         
         double beOffsetPoints = 0;
         ConvertValueToPoints(g_panelBEOffset, posVolume, beOffsetPoints);
         
         double newSL = 0;
         if(type == POSITION_TYPE_BUY)
         {
            newSL = openPrice + (beOffsetPoints * point);
            if(currentSL < newSL || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
         else if(type == POSITION_TYPE_SELL)
         {
            newSL = openPrice - (beOffsetPoints * point);
            if(currentSL > newSL || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Closure Functions                                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) trade.PositionClose(ticket);
   }
}

void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         trade.PositionClose(ticket);
   }
}

void CloseHalfPositions()
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double currentVolume = PositionGetDouble(POSITION_VOLUME);
         double closeVolume   = MathFloor((currentVolume / 2.0) / stepLot) * stepLot;
         if(closeVolume >= minLot && (currentVolume - closeVolume) >= minLot) trade.PositionClosePartial(ticket, closeVolume);
      }
   }
}

//+------------------------------------------------------------------+
//| Visual Pending Orders                                            |
//+------------------------------------------------------------------+
void CreatePendingLineUI(ENUM_PENDING_STATE state)
{
   RemovePendingLineUI();
   g_pendingState = state;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double linePrice = (state == PENDING_BUY) ? currentPrice - (100 * _Point) : currentPrice + (100 * _Point);
   color lineClr = (state == PENDING_BUY) ? clrGreen : clrRed;
   
   ObjectCreate(0, PENDING_LINE, OBJ_HLINE, 0, 0, linePrice);
   ObjectSetInteger(0, PENDING_LINE, OBJPROP_COLOR, lineClr);
   ObjectSetInteger(0, PENDING_LINE, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, PENDING_LINE, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, PENDING_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, PENDING_LINE, OBJPROP_SELECTED, true);
   
   CreateButton(BTN_PENDING_YES, "Yes", 0, 0, 45, 20, C'0,120,0', clrWhite);
   CreateButton(BTN_PENDING_NO, "No", 0, 0, 45, 20, C'150,0,0', clrWhite);
   UpdatePendingButtonsPosition();
   ChartRedraw();
}

void RemovePendingLineUI()
{
   g_pendingState = PENDING_NONE;
   ObjectDelete(0, PENDING_LINE);
   ObjectDelete(0, BTN_PENDING_YES);
   ObjectDelete(0, BTN_PENDING_NO);
   ChartRedraw();
}

void UpdatePendingButtonsPosition()
{
   if(g_pendingState == PENDING_NONE || ObjectFind(0, PENDING_LINE) < 0) return;
   double price = ObjectGetDouble(0, PENDING_LINE, OBJPROP_PRICE);
   int x, y;
   if(ChartTimePriceToXY(0, 0, TimeCurrent(), price, x, y))
   {
      int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      ObjectSetInteger(0, BTN_PENDING_YES, OBJPROP_XDISTANCE, chartWidth - 110);
      ObjectSetInteger(0, BTN_PENDING_YES, OBJPROP_YDISTANCE, y - 10);
      ObjectSetInteger(0, BTN_PENDING_NO, OBJPROP_XDISTANCE, chartWidth - 60);
      ObjectSetInteger(0, BTN_PENDING_NO, OBJPROP_YDISTANCE, y - 10);
   }
}

void ConfirmPendingOrder()
{
   if(g_pendingState == PENDING_NONE || ObjectFind(0, PENDING_LINE) < 0) return;
   
   double price = ObjectGetDouble(0, PENDING_LINE, OBJPROP_PRICE);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double lot = g_panelLot;
   double slPoints = 0, tpPoints = 0;
   if(g_useSL && g_panelSL > 0) ConvertValueToPoints(g_panelSL, lot, slPoints);
   if(g_useTP && g_panelTP > 0) ConvertValueToPoints(g_panelTP, lot, tpPoints);
   
   ENUM_ORDER_TYPE orderType;
   double slPrice = 0, tpPrice = 0;
   
   if(g_pendingState == PENDING_BUY)
   {
      orderType = (price < ask) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
      if(slPoints > 0) slPrice = price - (slPoints * point);
      if(tpPoints > 0) tpPrice = price + (tpPoints * point);
   }
   else
   {
      orderType = (price > bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
      if(slPoints > 0) slPrice = price + (slPoints * point);
      if(tpPoints > 0) tpPrice = price - (tpPoints * point);
   }
   
   trade.OrderOpen(_Symbol, orderType, lot, 0, price, slPrice, tpPrice, ORDER_TIME_GTC, 0, "Vis Pending");
   RemovePendingLineUI();
}

//+------------------------------------------------------------------+
//| انتخاب دستی پوزیشن + فعال/غیرفعال کردن BE و Trailing Stop تک‌تک   |
//| کاربر روی خط باز شدن پوزیشن مورد نظر روی چارت کلیک می‌کند (انتخاب)|
//| سپس دکمه TOGGLE BE/TS را می‌زند تا فقط همان پوزیشن خاموش/روشن شود |
//| لیست پوزیشن‌های خاموش‌شده در GlobalVariable ذخیره می‌شود تا بعد از |
//| بستن/باز کردن ترمینال یا ری‌استارت EA هم حفظ بماند.                |
//+------------------------------------------------------------------+
bool IsTicketBeTsExcluded(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_beTsExcludedTickets); i++)
      if(g_beTsExcludedTickets[i] == ticket) return true;
   return false;
}

// لیست فعلی استثناها را در GlobalVariable ذخیره می‌کند (ماندگار بین ری‌استارت‌های EA/ترمینال)
void PersistBeTsExcludedTickets()
{
   // ابتدا مقادیر قدیمی همان تعداد قبلی پاک می‌شوند تا اگر لیست کوچک‌تر شده، مقدار اضافه از دور قبل باقی نماند
   int oldCount = 0;
   if(GlobalVariableCheck(g_gvBeTsExclCountKey)) oldCount = (int)GlobalVariableGet(g_gvBeTsExclCountKey);
   for(int i = 0; i < oldCount; i++)
      GlobalVariableDel(g_gvBeTsExclPrefix + IntegerToString(i));

   int newCount = ArraySize(g_beTsExcludedTickets);
   GlobalVariableSet(g_gvBeTsExclCountKey, (double)newCount);
   for(int i = 0; i < newCount; i++)
      GlobalVariableSet(g_gvBeTsExclPrefix + IntegerToString(i), (double)g_beTsExcludedTickets[i]);
}

// خاموش/روشن‌کردن BE-Trailing برای یک تیکت خاص: اگر در لیست استثنا بود حذف می‌شود (روشن)، وگرنه اضافه می‌شود (خاموش)
void ToggleTicketBeTsExclusion(ulong ticket)
{
   if(ticket == 0) return;

   if(IsTicketBeTsExcluded(ticket))
   {
      ulong kept[];
      for(int i = 0; i < ArraySize(g_beTsExcludedTickets); i++)
      {
         if(g_beTsExcludedTickets[i] == ticket) continue;
         int n = ArraySize(kept);
         ArrayResize(kept, n + 1);
         kept[n] = g_beTsExcludedTickets[i];
      }
      ArrayFree(g_beTsExcludedTickets);
      ArrayCopy(g_beTsExcludedTickets, kept);
   }
   else
   {
      int n = ArraySize(g_beTsExcludedTickets);
      ArrayResize(g_beTsExcludedTickets, n + 1);
      g_beTsExcludedTickets[n] = ticket;
   }

   PersistBeTsExcludedTickets(); // هر بار تغییر لیست، بلافاصله ذخیره‌سازی می‌شود
}

// حذف تیکت‌های بسته‌شده از لیست استثنا تا آرایه بی‌رویه بزرگ نشود (دقیقا مشابه CleanupHedgedTickets)
void CleanupBeTsExcludedTickets()
{
   int prevCount = ArraySize(g_beTsExcludedTickets);

   ulong stillOpen[];
   for(int i = 0; i < ArraySize(g_beTsExcludedTickets); i++)
   {
      if(PositionSelectByTicket(g_beTsExcludedTickets[i]))
      {
         int n = ArraySize(stillOpen);
         ArrayResize(stillOpen, n + 1);
         stillOpen[n] = g_beTsExcludedTickets[i];
      }
   }
   ArrayFree(g_beTsExcludedTickets);
   ArrayCopy(g_beTsExcludedTickets, stillOpen);

   // فقط وقتی لیست واقعا تغییر کرده ذخیره‌سازی انجام شود، نه هر تیک (این تابع هر تیک صدا زده می‌شود)
   if(ArraySize(g_beTsExcludedTickets) != prevCount)
      PersistBeTsExcludedTickets();

   // اگر پوزیشن انتخاب‌شده فعلی دیگر باز نیست (بسته شده)، انتخاب پاک شود
   if(g_selectedPositionTicket != 0 && !PositionSelectByTicket(g_selectedPositionTicket))
   {
      g_selectedPositionTicket = 0;
      UpdateBeTsStatusLabel();
   }
}

// کلیک روی چارت (خارج از پنل و خارج از حالت رسم ترندلاین) را با خط قیمت باز شدن هر پوزیشن مقایسه می‌کند
// و نزدیک‌ترین پوزیشن در محدوده چند پیکسلی را به‌عنوان پوزیشن انتخاب‌شده علامت می‌زند.
void TrySelectPositionAtClick(int clickX, int clickY)
{
   const int CLICK_TOLERANCE_PX = 6;

   ulong  bestTicket = 0;
   int    bestDist   = CLICK_TOLERANCE_PX + 1;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int lineX, lineY;
      if(!ChartTimePriceToXY(0, 0, TimeCurrent(), openPrice, lineX, lineY)) continue;

      int dist = (int)MathAbs(clickY - lineY);
      if(dist <= CLICK_TOLERANCE_PX && dist < bestDist)
      {
         bestDist   = dist;
         bestTicket = ticket;
      }
   }

   if(bestTicket != 0)
   {
      g_selectedPositionTicket = bestTicket;
      UpdateBeTsStatusLabel();
   }
}

// متن و رنگ لیبل وضعیت را بر اساس پوزیشن انتخاب‌شده و اینکه BE/TS برایش روشن یا خاموش است به‌روز می‌کند
void UpdateBeTsStatusLabel()
{
   if(g_selectedPositionTicket == 0 || !PositionSelectByTicket(g_selectedPositionTicket))
   {
      ObjectSetString(0, LBL_BE_TS_STATUS, OBJPROP_TEXT, "پوزیشنی انتخاب نشده");
      ObjectSetInteger(0, LBL_BE_TS_STATUS, OBJPROP_COLOR, clrSilver);
      return;
   }

   bool excluded = IsTicketBeTsExcluded(g_selectedPositionTicket);
   string text = "#" + IntegerToString(g_selectedPositionTicket) + "  BE/TS: " + (excluded ? "OFF" : "ON");
   ObjectSetString(0, LBL_BE_TS_STATUS, OBJPROP_TEXT, text);
   ObjectSetInteger(0, LBL_BE_TS_STATUS, OBJPROP_COLOR, excluded ? clrOrange : clrLime);
}

//+------------------------------------------------------------------+
//| Break-Even & Trailing Stop Management                            |
//+------------------------------------------------------------------+
void ManageBreakEvenAndTrailing()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         if(IsTicketHedged(ticket)) continue; // پوزیشن قفل‌شده توسط هج خودکار؛ SL/TP نباید دوباره اضافه شود
         if(IsTicketBeTsExcluded(ticket)) continue; // کاربر دستی BE/Trailing را برای این پوزیشن خاموش کرده

         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double posVolume = PositionGetDouble(POSITION_VOLUME);
         double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         if(g_useBE && g_panelBE > 0)
         {
            double beTriggerPoints = 0, beOffsetPoints  = 0;
            ConvertValueToPoints(g_panelBE, posVolume, beTriggerPoints);
            ConvertValueToPoints(g_panelBEOffset, posVolume, beOffsetPoints);
            
            if(type == POSITION_TYPE_BUY && currentPrice - openPrice >= beTriggerPoints * point)
            {
               double newSL = openPrice + (beOffsetPoints * point);
               if(currentSL < newSL || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
            else if(type == POSITION_TYPE_SELL && openPrice - currentPrice >= beTriggerPoints * point)
            {
               double newSL = openPrice - (beOffsetPoints * point);
               if(currentSL > newSL || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         }
         
         if(g_useTS && g_panelTS > 0)
         {
            double tsDistancePoints = 0, tsStepPoints = 0;
            ConvertValueToPoints(g_panelTS, posVolume, tsDistancePoints);
            ConvertValueToPoints(g_panelTSStep, posVolume, tsStepPoints);
            
            if(type == POSITION_TYPE_BUY && currentPrice - openPrice > tsDistancePoints * point)
            {
               double newSL = currentPrice - (tsDistancePoints * point);
               if(newSL - currentSL >= tsStepPoints * point || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
            else if(type == POSITION_TYPE_SELL && openPrice - currentPrice > tsDistancePoints * point)
            {
               double newSL = currentPrice + (tsDistancePoints * point);
               if(currentSL - newSL >= tsStepPoints * point || currentSL == 0) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }

   CleanupBeTsExcludedTickets();
}

//+------------------------------------------------------------------+
//| Auto-Hedge Management (Requirement 1)                            |
//| در صورت رسیدن ضرر یک پوزیشن به آستانه تعیین‌شده، پوزیشن مخالفی    |
//| با همان حجم باز می‌شود و SL/TP هر دو پوزیشن حذف می‌گردد (قفل هج).  |
//+------------------------------------------------------------------+
bool IsTicketHedged(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_hedgedTickets); i++)
      if(g_hedgedTickets[i] == ticket) return true;
   return false;
}

void MarkTicketHedged(ulong ticket)
{
   if(ticket == 0 || IsTicketHedged(ticket)) return;
   int n = ArraySize(g_hedgedTickets);
   ArrayResize(g_hedgedTickets, n + 1);
   g_hedgedTickets[n] = ticket;
}

// حذف تیکت‌های بسته‌شده از لیست هج تا آرایه بی‌رویه بزرگ نشود
void CleanupHedgedTickets()
{
   ulong stillOpen[];
   for(int i = 0; i < ArraySize(g_hedgedTickets); i++)
   {
      if(PositionSelectByTicket(g_hedgedTickets[i]))
      {
         int n = ArraySize(stillOpen);
         ArrayResize(stillOpen, n + 1);
         stillOpen[n] = g_hedgedTickets[i];
      }
   }
   ArrayFree(g_hedgedTickets);
   ArrayCopy(g_hedgedTickets, stillOpen);
}

// تبدیل مقدار «Hedge Loss» به مبلغ پول (ارز حساب) بر اساس Mode انتخاب‌شده (POINTS/USD/PERCENT)،
// دقیقا مشابه منطقی که برای SL/TP/BE/TS استفاده می‌شود؛ چون حجم هر پوزیشن می‌تواند متفاوت باشد،
// در حالت POINTS تبدیل بر اساس حجم همان پوزیشن خاص انجام می‌شود.
double GetHedgeLossThresholdMoney(double positionVolume)
{
   double val = MathAbs(g_panelHedgeLoss);

   if(g_calcMode == MODE_USD) return val;

   if(g_calcMode == MODE_PERCENT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      return balance * (val / 100.0);
   }

   // MODE_POINTS: تبدیل تعداد پوینت به مبلغ زیان معادل، بر اساس حجم همان پوزیشن
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickValue <= 0 || tickSize <= 0 || point <= 0 || positionVolume <= 0) return val;

   double valuePerPoint = tickValue * (point / tickSize) * positionVolume;
   return val * valuePerPoint;
}

void ManageAutoHedge()
{
   if(!g_useHedge || g_panelHedgeLoss <= 0) return;

   // هج واقعی (نگه‌داشتن هم‌زمان دو پوزیشن مخالف) فقط روی حساب‌های Hedging امکان‌پذیر است.
   // در حساب‌های Netting، پوزیشن مخالف باعث نتینگ/بستن پوزیشن اصلی می‌شود، پس این تابع در آن حالت غیرفعال می‌ماند.
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(IsTicketHedged(ticket)) continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); // POSITION_COMMISSION در MQL5 برای پوزیشن باز وجود ندارد
      double volume = PositionGetDouble(POSITION_VOLUME);
      double hedgeThresholdMoney = GetHedgeLossThresholdMoney(volume);
      if(hedgeThresholdMoney <= 0) continue;
      if(profit > -hedgeThresholdMoney) continue; // هنوز به آستانه ضرر نرسیده

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      ENUM_ORDER_TYPE hedgeType  = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double          hedgePrice = (hedgeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      bool sent = (hedgeType == ORDER_TYPE_BUY)
                  ? trade.Buy(volume, _Symbol, hedgePrice, 0, 0, "Auto Hedge")
                  : trade.Sell(volume, _Symbol, hedgePrice, 0, 0, "Auto Hedge");

      if(sent)
      {
         ulong hedgeTicket = trade.ResultOrder();

         trade.PositionModify(ticket, 0, 0); // حذف SL/TP پوزیشن اصلی (زیان‌ده)
         Sleep(200);                          // اجازه ثبت کامل پوزیشن جدید در سرور
         if(hedgeTicket > 0 && PositionSelectByTicket(hedgeTicket))
            trade.PositionModify(hedgeTicket, 0, 0); // حذف SL/TP پوزیشن هج جدید

         MarkTicketHedged(ticket);
         if(hedgeTicket > 0) MarkTicketHedged(hedgeTicket);

         Print("Auto-Hedge: locked ticket #", ticket, " with opposite ticket #", hedgeTicket, " (volume ", DoubleToString(volume, 2), ")");
      }
      else
      {
         Print("Auto-Hedge failed for ticket #", ticket, ", error code: ", GetLastError());
      }
   }

   CleanupHedgedTickets();
}

//+------------------------------------------------------------------+
//| Trendline Logic (Requirements 2, 3, 4, 5)                         |
//+------------------------------------------------------------------+

// آیا این نام متعلق به خطی است که توسط اکسپرت ساخته/مدیریت می‌شود؟
// شامل خط قدیمی و ثابت (InpTrendlineName) و همه خطوط خودکار با پیشوند Ali_ می‌شود.
bool IsEATrendline(const string name)
{
   if(name == InpTrendlineName) return true;
   if(StringFind(name, InpAutoTrendlinePrefix + "_") == 0) return true;
   return false;
}

int FindTLStateIndex(const string name)
{
   for(int i = 0; i < ArraySize(g_tlStates); i++)
      if(g_tlStates[i].name == name) return i;
   return -1;
}

// حذف رکوردهای وضعیت مربوط به خطوطی که دیگر روی چارت وجود ندارند (پاک شده‌اند)
void CleanupTLStates()
{
   STLState kept[];
   for(int i = 0; i < ArraySize(g_tlStates); i++)
   {
      if(ObjectFind(0, g_tlStates[i].name) >= 0)
      {
         int n = ArraySize(kept);
         ArrayResize(kept, n + 1);
         kept[n] = g_tlStates[i];
      }
   }
   ArrayFree(g_tlStates);
   int total = ArraySize(kept);
   if(total > 0)
   {
      ArrayResize(g_tlStates, total);
      for(int i = 0; i < total; i++) g_tlStates[i] = kept[i];
   }
}

// نقطه خام (زمان/قیمت) زیر ماوس را به نزدیک‌ترین نقطه واقعی کندل (بدنه یا سایه) می‌چسباند - مثل مگنت.
// نزدیک‌ترین کندل با iBarShift پیدا می‌شود، سپس از بین Open/High/Low/Close همان کندل، نزدیک‌ترین به قیمت خام انتخاب می‌شود.
bool SnapToCandle(datetime rawTime, double rawPrice, datetime &snapTime, double &snapPrice)
{
   int idx = iBarShift(_Symbol, _Period, rawTime, false);
   if(idx < 0) return false;

   double o = iOpen(_Symbol, _Period, idx);
   double h = iHigh(_Symbol, _Period, idx);
   double l = iLow(_Symbol, _Period, idx);
   double c = iClose(_Symbol, _Period, idx);
   if(o == 0 || h == 0 || l == 0 || c == 0) return false; // دیتای کندل هنوز آماده نیست

   double best = h;
   double bestDist = MathAbs(rawPrice - h);
   double dO = MathAbs(rawPrice - o); if(dO < bestDist) { bestDist = dO; best = o; }
   double dL = MathAbs(rawPrice - l); if(dL < bestDist) { bestDist = dL; best = l; }
   double dC = MathAbs(rawPrice - c); if(dC < bestDist) { bestDist = dC; best = c; }

   snapPrice = best;
   snapTime  = iTime(_Symbol, _Period, idx);
   return true;
}

// خط پیش‌نمایش موقت که از لحظه کلیک نقطه اول تا رسیدن به کلیک نقطه دوم، همراه حرکت ماوس روی چارت دیده می‌شود (Requirement 1).
void CreateTrendlinePreview(datetime t1, double p1)
{
   RemoveTrendlinePreview();
   ObjectCreate(0, TL_PREVIEW_LINE, OBJ_TREND, 0, t1, p1, t1, p1);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_BACK, false);
   ObjectSetInteger(0, TL_PREVIEW_LINE, OBJPROP_ZORDER, 5);
}

void UpdateTrendlinePreview(datetime t2, double p2)
{
   if(ObjectFind(0, TL_PREVIEW_LINE) < 0) return;
   ObjectMove(0, TL_PREVIEW_LINE, 1, t2, p2);
}

void RemoveTrendlinePreview()
{
   if(ObjectFind(0, TL_PREVIEW_LINE) >= 0) ObjectDelete(0, TL_PREVIEW_LINE);
}

// ساخت خط روند جدید با نام‌گذاری خودکار Ali_1، Ali_2 و ... بر اساس دو نقطه‌ای که خود کاربر
// با دو کلیک روی چارت مشخص کرده است (Requirement 2 & 3). هیچ خطی به‌صورت خودکار ظاهر نمی‌شود.
void CreateNewTrendline(datetime t1, double p1, datetime t2, double p2)
{
   g_trendlineCounter++;
   string name = InpAutoTrendlinePrefix + "_" + IntegerToString(g_trendlineCounter);
   while(ObjectFind(0, name) >= 0) // احتیاط در برابر برخورد نام در صورت ساخت دستی نام مشابه توسط کاربر
   {
      g_trendlineCounter++;
      name = InpAutoTrendlinePrefix + "_" + IntegerToString(g_trendlineCounter);
   }

   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); // ضخامت نازک طبق درخواست
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); // امتداد به سمت راست تا لمس قیمت در آینده هم تشخیص داده شود
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);

   GlobalVariableSet(g_gvTLCounterKey, (double)g_trendlineCounter);

   // جلوگیری از معامله فوری در همان کندلی که خط ساخته شده؛ معامله فقط از کندل بعدی به بعد بررسی می‌شود
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   int idx = FindTLStateIndex(name);
   if(idx < 0)
   {
      int n = ArraySize(g_tlStates);
      ArrayResize(g_tlStates, n + 1);
      g_tlStates[n].name = name;
      g_tlStates[n].lastBarTime = currentBarTime;
   }
   else
      g_tlStates[idx].lastBarTime = currentBarTime;

   ChartRedraw();
   Print("New EA trendline created: ", name);
}

// حذف تمام خطوطی که توسط اکسپرت ساخته شده‌اند و ریست شمارنده از صفر (Requirement: دکمه پاک‌کردن همه خطوط)
void ClearAllEATrendlines()
{
   int total = ObjectsTotal(0, 0, OBJ_TREND);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_TREND);
      if(IsEATrendline(name)) ObjectDelete(0, name);
   }

   ArrayFree(g_tlStates);
   g_trendlineCounter = 0;
   GlobalVariableSet(g_gvTLCounterKey, 0.0);
   ChartRedraw();
   Print("All EA trendlines cleared. Counter reset - next line will be ", InpAutoTrendlinePrefix, "_1.");
}

// بررسی می‌کند که آیا دیگر هیچ خط EA روی چارت باقی نمانده (مثلا با حذف دستی تک‌تک خطوط)؛
// در این صورت شمارنده مجددا از صفر شروع می‌شود تا خط بعدی Ali_1 نام‌گذاری شود.
void CheckIfAllTrendlinesCleared()
{
   if(g_trendlineCounter == 0) return;

   int total = ObjectsTotal(0, 0, OBJ_TREND);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, OBJ_TREND);
      if(IsEATrendline(name)) return; // حداقل یک خط EA هنوز روی چارت وجود دارد
   }

   g_trendlineCounter = 0;
   GlobalVariableSet(g_gvTLCounterKey, 0.0);
   ArrayFree(g_tlStates);
   Print("All EA trendlines are gone - counter reset. Next line will be ", InpAutoTrendlinePrefix, "_1.");
}

void CheckTrendlineTouch()
{
   if(GetTotalOpenPositionsCount() > 0) return;

   datetime timeCurrent     = TimeCurrent();
   datetime currentBarTime  = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   double   bid             = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double   point           = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double   tol             = InpTolerancePoints * point;

   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 1, rates) <= 0) return;
   double prevClose = rates[0].close;

   int total = ObjectsTotal(0, 0, OBJ_TREND);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_TREND);
      if(!IsEATrendline(name)) continue; // Requirement 4: فقط خطوط ساخته‌شده توسط اکسپرت بررسی شوند

      int idx = FindTLStateIndex(name);
      if(idx < 0)
      {
         int n = ArraySize(g_tlStates);
         ArrayResize(g_tlStates, n + 1);
         g_tlStates[n].name = name;
         g_tlStates[n].lastBarTime = 0;
         idx = n;
      }

      if(g_tlStates[idx].lastBarTime == currentBarTime) continue; // این خط در این کندل قبلا پردازش شده

      double linePrice = ObjectGetValueByTime(0, name, timeCurrent, 0);
      if(linePrice <= 0) continue;

      bool tradeExecuted = false;

      if(prevClose < linePrice && bid >= (linePrice - tol) && bid <= (linePrice + tol))
      {
         if(ExecuteTrade(ORDER_TYPE_SELL))
         {
            tradeExecuted = true;
            if(InpEnableSoundAlert) PlaySound(InpSoundFileName);
         }
      }
      else if(prevClose > linePrice && bid <= (linePrice + tol) && bid >= (linePrice - tol))
      {
         if(ExecuteTrade(ORDER_TYPE_BUY))
         {
            tradeExecuted = true;
            if(InpEnableSoundAlert) PlaySound(InpSoundFileName);
         }
      }

      if(tradeExecuted)
      {
         g_tlStates[idx].lastBarTime = currentBarTime; // Requirement 4: فقط همین خط علامت‌گذاری می‌شود، نه بقیه خطوط
         break; // یک معامله در هر تیک کافی است
      }
   }

   CleanupTLStates();
}