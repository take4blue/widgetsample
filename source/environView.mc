import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Time;
using Toybox.System as Sys;

const propIndex = "index";

//! Page生成のためのファクトリークラス
class EnvironIndicatorFactory extends WatchUi.ViewLoopFactory {
    function initialize() {
        ViewLoopFactory.initialize();
    }

    //! Retrieve a view/delegate pair for the page at the given index
    function getView(page as Number) as [ViewLoopFactory.Views] or [ViewLoopFactory.Views, ViewLoopFactory.Delegates] {
        // delegateが無いとエラーになるのでベースのdelegateを入れる
        return [new $.EnvironView(page, false), new WatchUi.BehaviorDelegate()];
    }

    // ページサイズ
    function getSize() {
        return EnvironView.NUM_PAGES;
    }
}

//! 読み込むセンサーパラメータタイプ(構造体の設定ができないためArrayで中身の型指定で代用)
//! 0:Iteratorシンボル, 1:最小値, 2:最大値, 3:取得間隔(秒),
//! 5:レシオ, 6:センサーラベル
typedef SensorParameter as [Symbol, Number, Number, Number, Number, ResourceId?];
const spSymbol = 0;
const spMin = 1;
const spMax = 2;
const spDuration = 3;
const spRatio = 4;
const spLabel = 5;

//! 環境情報を表示するクラス
(:glance)
class EnvironView extends WatchUi.View {
    static const viewFont = Graphics.FONT_XTINY;
    static const glanceFont = Graphics.FONT_XTINY;

    static const xSpace = 15; // グラフ領域左右のスペース

    static const NUM_PAGES = 7;
    private const _parameters as Array<SensorParameter> = [
        [:getHeartRateHistory, 50, 120, 14400, 1, Rez.Strings.ViewHeartRateLabel],
        [:getTemperatureHistory, 25, 45, 14400, 1, Rez.Strings.ViewTempLabel],
        [:getPressureHistory, 80000, 103000, 14400, 100, Rez.Strings.ViewPressureLabel],
        [:getElevationHistory, 0, 500, 14400, 1, Rez.Strings.ViewElevationLabel],
        [:getOxygenSaturationHistory, 80, 100, 14400, 1, Rez.Strings.ViewOxygenLabel],
        [:getStressHistory, 0, 100, 28800, 1, Rez.Strings.ViewStressLabel],
        [:getBodyBatteryHistory, 0, 100, 28800, 1, Rez.Strings.ViewBodyBatteryLabel],
    ];

    private var _width as Number = 0;
    private var _height as Number = 0;
    private var _graphHeight as Number = 0;
    private var _graphBottom as Number = 0;

    private var _glanceMode as Boolean = false;

    //! 現在使用しているセンサーパラメーター
    private var _param as SensorParameter;

    //! Constructor
    //! @param page 表示するページ番号(0オリジン), nullの場合はパラメータ内の値を使用する
    //! @param glanceMode Whether the view is in glance mode
    public function initialize(page as Number or Null, glanceMode as Boolean) {
        View.initialize();

        var index = 0;

        if (page != null) {
            index = page;
            if (Application has :Properties) {
                Application.Properties.setValue(propIndex, index);
            }
        }
        else if (Application has :Properties) {
            index = Application.Properties.getValue(propIndex);
        }
        _glanceMode = glanceMode;
        _param = _parameters[index % NUM_PAGES];
    }

    //! 表示するページの設定(利用者は EnvironDelegate だけかな)
    public function setPage(page as Number) as Void {
        _param = _parameters[page % NUM_PAGES];
        if (Application has :Properties) {
            Application.Properties.setValue(propIndex, page % NUM_PAGES);
        }
    }

    public function onLayout(dc as Dc) as Void {
        _width = dc.getWidth();
        _height = dc.getHeight();
        if (_glanceMode) {
            var fontHeight = dc.getFontHeight(glanceFont);
            _graphHeight = _height - (1 * fontHeight);   // 描画領域の高さ(固定)
            _graphBottom = _height;
        }
        else {
            var fontHeight = dc.getFontHeight(viewFont);
            _graphHeight = _height - (6 * fontHeight);   // 描画領域の高さ(固定)
            _graphBottom = (_height + _graphHeight) / 2;
        }
    }

    //! Get the iterator for the current sensor
    //! @return The iterator for the current sensor
    private function getIterator() as SensorHistoryIterator? {
        if ((Toybox has :SensorHistory) && (SensorHistory has _param[spSymbol])) {
            var getMethod = new Lang.Method(SensorHistory, _param[spSymbol]);
            return getMethod.invoke({
                :period => new Duration(_param[spDuration]),
                :order => SensorHistory.ORDER_NEWEST_FIRST,
            }) as SensorHistoryIterator;
        }
        return null;
    }

    private function toDateString(time as Moment) as String {
        var info = Gregorian.info(time, Time.FORMAT_SHORT);
        return Lang.format("$1$/$2$ $3$:$4$", [
            (info.month as Number).format("%d"),
            info.day.format("%d"),
            info.hour.format("%02d"),
            info.min.format("%02d")
        ]);
    }

    //! センサーグラフの描画
    //! @return [最大値、最小値、最初のサンプルデータ、最初のサンプル時刻] だったら描画成功、nullだったら描画失敗
    private function drawGraph(dc as Dc, sensorIter as SensorHistoryIterator, count as Number) as
      [Number or Float, Number or Float, Number or Float or Null, Moment] or Null {
        if (count < 2) {
            // 描画データが無い場合はnullを返す
            return null;
        }

        var minmax = [sensorIter.getMin(), sensorIter.getMax()];
        // 表示領域を決定するための最小値・最大値を求める
        // SensorParameterの最大最小値とセンサーの最大最小値を比較して、より広い範囲を使用する
        var graphMin = minmax[0];
        graphMin = (graphMin == null || graphMin > _param[spMin]) ? _param[spMin] : graphMin;
        var graphMax = minmax[1];
        graphMax = (graphMax == null || graphMax < _param[spMax]) ? _param[spMax] : graphMax;

        Sys.println(Lang.format("$1$ $2$", minmax));

        var dataOffset = graphMin.toFloat();
        var margin = _width - xSpace;
        var yScaler = _graphHeight / (graphMax - graphMin).toFloat();

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);

        var xStep = 1.0f * (_width - (2 * xSpace)) / (count - 1);

        var gotValidData = false;   // グラフの描画を行ったらtrue(データが2個以上ある場合trueともいう)
        // 欠損情報もあるため、y1/y2を毎回求めなおすようにしている
        var previous = sensorIter.next();
        var firstData = previous;
        var sample = sensorIter.next();
        var i = 0;
        // グラフは右(最新)から左(古い)に描画する
        while ((null != previous) && (null != sample)) {
            var previousData = previous.data;
            var sampleData = sample.data;
            if ((sampleData != null) && (previousData != null)) {
                var x1 = margin - (xStep * i);
                var x2 = margin - (xStep * (i + 1));
                var y1 = _graphBottom - (previousData - dataOffset) * yScaler;
                var y2 = _graphBottom - (sampleData - dataOffset) * yScaler;

                dc.drawLine(x1, y1, x2, y2);
                gotValidData = true;
            }

            ++i;
            previous = sample;
            sample = sensorIter.next();
        }
        return gotValidData ? [minmax[0], minmax[1], firstData.data, firstData.when] : null;
    }

    private function getTitle(data as Number or Float or Null) as String {
        if (data != null) {
            return loadResource(_param[spLabel]) + ": " + (data / _param[spRatio]).format("%d");
        }
        else {
            return loadResource(_param[spLabel]);
        }
    }

    private function drawGlanceText(dc as Dc, data as Number or Float or Null) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, 0, glanceFont, getTitle(data), Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! センサーのテキスト関連の情報出力
    private function drawViewText(dc as Dc, result as [Number or Float, Number or Float, Number or Float or Null, Moment]) as Void {
        var fontHeight = dc.getFontHeight(viewFont);
        var halfWidth = _width / 2;

        // draw the min/max hr values
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        dc.drawText(halfWidth, 1 * fontHeight, viewFont, getTitle(result[2]), Graphics.TEXT_JUSTIFY_CENTER);
        var min = (result[0] / _param[spRatio]).format("%d");
        var max = (result[1] / _param[spRatio]).format("%d");
        dc.drawText(halfWidth, 2 * fontHeight, viewFont, "Min: " + min + " Max: " + max, Graphics.TEXT_JUSTIFY_CENTER);

        // draw the start/end times
        var startString = toDateString(result[3]);
        dc.drawText(halfWidth, _height - (3 * fontHeight), viewFont, startString, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(halfWidth, _height - (2 * fontHeight), viewFont,
            Lang.format(loadResource(Rez.Strings.PastLabel), [_param[spDuration] / 3600]), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Update the view
    //! @param dc Device context
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var message = "";
        if (Toybox has :SensorHistory) {
            var sensorIter = getIterator();
            if (sensorIter != null) {
                var count = 0;
                for (var data = sensorIter.next(); data != null; data = sensorIter.next(), count++){}
                Sys.println(count.toString());
                sensorIter = getIterator();
                var result = drawGraph(dc, sensorIter, count);
                if (result != null) {
                   if (!_glanceMode) {
                        drawViewText(dc, result);
                    }
                    else {
                        drawGlanceText(dc, result[2]);
                    }
                } else {
                    message = loadResource(_param[spLabel]) + "\nNo data available.";
                }
             } else {
                message = loadResource(_param[spLabel]) + "\nSensor not available";
            }
        } else {
            message = "Sensor History\nNot Supported";
        }

        if (message != "") {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(_width / 2, _height / 2, _glanceMode ? Graphics.FONT_GLANCE_NUMBER : Graphics.FONT_MEDIUM,
                message, (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
        }
    }
}

// ViewLoop機能が無い場合にviewを切り替えるためのdelegate
class EnvironDelegate extends WatchUi.BehaviorDelegate {
    private var _view as EnvironView;
    private var _index as Number = 0;

    //! Constructor
    public function initialize(view as EnvironView) {
        BehaviorDelegate.initialize();
        _view = view;
        if (Application has :Properties) {
            _index = Application.Properties.getValue(propIndex);
        }
    }

    public function onNextPage() as Boolean {
        _index++;
        _index %= EnvironView.NUM_PAGES;
        _view.setPage(_index);
        WatchUi.requestUpdate();
        return true;
    }

    public function onPreviousPage() as Boolean {
        _index += EnvironView.NUM_PAGES - 1;
        _index %= EnvironView.NUM_PAGES;
        _view.setPage(_index);
        WatchUi.requestUpdate();
        return true;
    }
}

(:glance)
class EnvironGlanceView extends WatchUi.GlanceView {
    private var _view as EnvironView;

    //! Constructor
    public function initialize(view as EnvironView) {
        GlanceView.initialize();
        _view = view;
    }

    public function onLayout(dc as Dc) as Void {
        _view.onLayout(dc);
    }

    public function onUpdate(dc as Dc) as Void {
       _view.onUpdate(dc);
    }
}