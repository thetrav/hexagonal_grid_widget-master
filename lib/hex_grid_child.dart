import 'package:flutter/widgets.dart';
import 'package:hexagonal_grid/hexagonal_grid.dart';
import 'hex_grid_context.dart';

abstract class HexGridChild {

  Widget toHexWidget(
    BuildContext context,
    HexGridContext hexGridContext,
    Hex hex);

}
