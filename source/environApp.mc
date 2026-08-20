import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class EnvironApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var index = 0;
        if (Application has :Properties) {
            index = Application.Properties.getValue(propIndex);
        }
        if (WatchUi has :ViewLoop) {
            var factory = new EnvironIndicatorFactory();
            var viewLoop = new WatchUi.ViewLoop(factory, {:page => index});
            // 特殊なページ操作を行う場合はdelegateを独自作成して呼び出す
            return [viewLoop, new ViewLoopDelegate(viewLoop)];
        } else {
            var view = new EnvironView(index, false);
            return [view, new EnvironDelegate(view)];
        }
    }

    function getGlanceView() as [ WatchUi.GlanceView ] or [ WatchUi.GlanceView, WatchUi.GlanceViewDelegate ] or Null {
        return [new EnvironGlanceView(new EnvironView(null, true))];
    }
}

function getApp() as EnvironApp {
    return Application.getApp() as EnvironApp;
}